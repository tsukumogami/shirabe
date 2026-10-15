//! The quote-aware tokenizer both entry points share.
//!
//! It reads a Bash command the way the shell splits it, closely enough not to
//! lose a guarded command in it, and evaluates nothing. A command becomes
//! segments: the pieces between unquoted `;`, `&`, `|`, newline, `(` and `)`
//! (PRD Definitions). Each segment holds its words after quote removal and the
//! parenthesis groups it sits in, so the classifier can end a `cd` when its
//! subshell closes.
//!
//! Command substitutions (`$(...)` and backquotes, outside single quotes) are
//! scanned as commands of their own, one recursion level each, and recorded
//! with their spans; the word that holds one keeps the substitution's text
//! as written, so the body reader can refuse it. A here-document's lines are
//! consumed as data at the newline that follows its operator and recorded
//! apart, never split into segments: `git commit -m "$(cat <<'EOF' ... git
//! push ... EOF)"` holds no `git push` segment, and an apostrophe on one of
//! its lines can't unbalance the outer command.
//!
//! Not a full shell parser. `case` patterns, arithmetic and functions are read
//! loosely; what matters is that a quote or a here-document never makes a
//! segment boundary disappear, and that an unterminated quote or substitution
//! is reported rather than guessed at.

use std::ops::Range;

/// One word of a segment: its text after quote removal, plus what the quoting
/// hid. A `$`, backquote or `$'` is kept in `text` as written.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Word {
    pub text: String,
    /// Byte span of the word in the text it was scanned from.
    pub span: Range<usize>,
    /// No quote or backslash anywhere in the word.
    pub bare: bool,
    /// An unquoted or double-quoted `$` expansion, `$(...)` or backquote.
    pub expansion: bool,
    /// A `$'...'` piece, left as written.
    pub ansi_c: bool,
    /// Starts with an unquoted `~`, which the shell would expand.
    pub tilde: bool,
    /// The here-document this word's `<<` operator opened, as an index into
    /// [`Tokenized::heredocs`].
    pub heredoc: Option<usize>,
    /// The word is exactly one double-quoted command substitution,
    /// `"$(...)"`; the index into [`Tokenized::substitutions`].
    pub dq_substitution: Option<usize>,
}

/// The words between two unquoted separators.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Segment {
    pub words: Vec<Word>,
    /// The parenthesis groups enclosing the segment, outermost first. Each id
    /// is unique within one [`Tokenized`], so two sibling groups at the same
    /// depth never look like one.
    pub groups: Vec<usize>,
}

/// A command substitution: its span in the scanned text (the part between
/// `$(` and `)`, or between the backquotes) and its own tokenized contents.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Substitution {
    pub span: Range<usize>,
    pub inner: Tokenized,
}

/// A here-document's lines, which are data, not commands.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HereDoc {
    pub delimiter: String,
    /// The delimiter was quoted (`'EOF'`, `"EOF"`, `\EOF`), so the shell
    /// expands nothing in the lines.
    pub quoted: bool,
    /// The `<<-` form, whose lines lose their leading tabs.
    pub strip_tabs: bool,
    /// The lines, each followed by `\n`, as the shell would feed them.
    pub body: String,
    /// A line equal to the delimiter ended it (rather than the end of input).
    pub terminated: bool,
}

/// A tokenized command.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Tokenized {
    pub segments: Vec<Segment>,
    pub substitutions: Vec<Substitution>,
    pub heredocs: Vec<HereDoc>,
}

/// Why a command could not be tokenized: an unterminated quote, `$(...)`,
/// `${...}` or backquote (PRD R7 case 3).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Unterminated;

/// Tokenize `cmd`. A backslash followed by a newline outside single quotes is
/// removed, joining the two lines as the shell does.
pub fn tokenize(cmd: &str) -> Result<Tokenized, Unterminated> {
    let mut sc = Scanner {
        s: cmd.as_bytes(),
        i: 0,
    };
    sc.scan(End::Eof)
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum End {
    Eof,
    /// The `)` that closes a `$(`.
    Paren,
}

struct Scanner<'a> {
    s: &'a [u8],
    i: usize,
}

/// The state of one recursion level: the segment and word being built.
struct Level {
    out: Tokenized,
    words: Vec<Word>,
    cur: Vec<u8>,
    word: Word,
    in_word: bool,
    start: usize,
    groups: Vec<usize>,
    next_group: usize,
    /// Here-documents whose lines start at the next newline, with their
    /// indexes in `out.heredocs`.
    pending: Vec<usize>,
}

impl Level {
    fn new() -> Self {
        Level {
            out: Tokenized::default(),
            words: Vec::new(),
            cur: Vec::new(),
            word: Word {
                bare: true,
                ..Word::default()
            },
            in_word: false,
            start: 0,
            groups: Vec::new(),
            next_group: 0,
            pending: Vec::new(),
        }
    }

    fn begin(&mut self, at: usize) {
        if !self.in_word {
            self.in_word = true;
            self.start = at;
        }
    }

    /// End the word being built at byte `at` of `s`, the text scanned.
    fn end_word(&mut self, s: &[u8], at: usize) {
        if !self.in_word {
            return;
        }
        let mut w = std::mem::replace(
            &mut self.word,
            Word {
                bare: true,
                ..Word::default()
            },
        );
        w.text = String::from_utf8_lossy(&std::mem::take(&mut self.cur)).into_owned();
        w.span = self.start..at;
        // `"$(...)"` alone: the word opens with `"$(`, closes with `)"`, and
        // one substitution spans everything between.
        let word = &s[self.start..at];
        if word.starts_with(b"\"$(") && word.ends_with(b")\"") && word.len() >= 5 {
            w.dq_substitution = self
                .out
                .substitutions
                .iter()
                .position(|sub| sub.span == (self.start + 3..at - 2));
        }
        self.words.push(w);
        self.in_word = false;
    }

    fn end_segment(&mut self, s: &[u8], at: usize) {
        self.end_word(s, at);
        if !self.words.is_empty() {
            self.out.segments.push(Segment {
                words: std::mem::take(&mut self.words),
                groups: self.groups.clone(),
            });
        }
    }
}

impl<'a> Scanner<'a> {
    fn peek(&self, off: usize) -> Option<u8> {
        self.s.get(self.i + off).copied()
    }

    fn scan(&mut self, end: End) -> Result<Tokenized, Unterminated> {
        let mut lv = Level::new();
        loop {
            let Some(c) = self.peek(0) else {
                if end == End::Paren {
                    return Err(Unterminated);
                }
                lv.end_segment(self.s, self.i);
                return Ok(lv.out);
            };
            match c {
                b'\'' => {
                    lv.begin(self.i);
                    lv.word.bare = false;
                    let close = self.s[self.i + 1..]
                        .iter()
                        .position(|&b| b == b'\'')
                        .ok_or(Unterminated)?;
                    lv.cur
                        .extend_from_slice(&self.s[self.i + 1..self.i + 1 + close]);
                    self.i += close + 2;
                }
                b'"' => {
                    lv.begin(self.i);
                    lv.word.bare = false;
                    self.double_quoted(&mut lv)?;
                }
                b'\\' => match self.peek(1) {
                    // A backslash-newline joins the lines and is removed.
                    Some(b'\n') => self.i += 2,
                    Some(n) => {
                        lv.begin(self.i);
                        lv.word.bare = false;
                        lv.cur.push(n);
                        self.i += 2;
                    }
                    None => {
                        lv.begin(self.i);
                        lv.cur.push(b'\\');
                        self.i += 1;
                    }
                },
                b'$' => {
                    lv.begin(self.i);
                    self.dollar(&mut lv, false)?;
                }
                b'`' => {
                    lv.begin(self.i);
                    self.backquote(&mut lv)?;
                }
                b'#' if !lv.in_word => {
                    while let Some(b) = self.peek(0) {
                        if b == b'\n' {
                            break;
                        }
                        self.i += 1;
                    }
                }
                b'\n' => {
                    lv.end_segment(self.s, self.i);
                    self.i += 1;
                    self.heredoc_lines(&mut lv, end);
                }
                b'&' | b'|' | b';' => {
                    // `>&`, `<&`, `&>` and `>|` are redirections, not
                    // separators: `2>&1` stays one word.
                    let redirect = (lv.in_word
                        && c != b';'
                        && matches!(lv.cur.last(), Some(b'>') | Some(b'<')))
                        || (c == b'&' && self.peek(1) == Some(b'>'));
                    if redirect {
                        lv.begin(self.i);
                        lv.cur.push(c);
                    } else {
                        lv.end_segment(self.s, self.i);
                    }
                    self.i += 1;
                }
                b'(' => {
                    lv.end_segment(self.s, self.i);
                    lv.groups.push(lv.next_group);
                    lv.next_group += 1;
                    self.i += 1;
                }
                b')' => {
                    lv.end_segment(self.s, self.i);
                    self.i += 1;
                    if lv.groups.pop().is_none() && end == End::Paren {
                        return Ok(lv.out);
                    }
                }
                b'<' if self.peek(1) == Some(b'<') => {
                    if self.peek(2) == Some(b'<') {
                        // `<<<`, a here-string: an ordinary word.
                        lv.begin(self.i);
                        lv.cur.extend_from_slice(b"<<<");
                        self.i += 3;
                    } else {
                        lv.end_word(self.s, self.i);
                        self.heredoc_operator(&mut lv);
                    }
                }
                b' ' | b'\t' | b'\r' => {
                    lv.end_word(self.s, self.i);
                    self.i += 1;
                }
                _ => {
                    if !lv.in_word && c == b'~' {
                        lv.word.tilde = true;
                    }
                    lv.begin(self.i);
                    lv.cur.push(c);
                    self.i += 1;
                }
            }
        }
    }

    /// A `"..."` piece, the scanner on its opening quote. Inside, a backslash
    /// escapes only `"`, `\`, `$` and backquote (and a newline, which it
    /// removes); `$` and backquotes still expand.
    fn double_quoted(&mut self, lv: &mut Level) -> Result<(), Unterminated> {
        self.i += 1;
        loop {
            match self.peek(0) {
                None => return Err(Unterminated),
                Some(b'"') => {
                    self.i += 1;
                    break;
                }
                Some(b'\\') => match self.peek(1) {
                    Some(b'\n') => self.i += 2,
                    Some(n @ (b'"' | b'\\' | b'$' | b'`')) => {
                        lv.cur.push(n);
                        self.i += 2;
                    }
                    Some(n) => {
                        lv.cur.push(b'\\');
                        lv.cur.push(n);
                        self.i += 2;
                    }
                    None => return Err(Unterminated),
                },
                Some(b'$') => self.dollar(lv, true)?,
                Some(b'`') => {
                    self.backquote(lv)?;
                }
                Some(c) => {
                    lv.cur.push(c);
                    self.i += 1;
                }
            }
        }
        Ok(())
    }

    /// A `$` piece, the scanner on the `$`.
    fn dollar(&mut self, lv: &mut Level, in_dq: bool) -> Result<(), Unterminated> {
        let start = self.i;
        match self.peek(1) {
            Some(b'(') => {
                lv.word.expansion = true;
                self.i += 2;
                let inner_start = self.i;
                let inner = self.scan(End::Paren)?;
                let inner_end = self.i - 1;
                lv.out.substitutions.push(Substitution {
                    span: inner_start..inner_end,
                    inner,
                });
                lv.cur.extend_from_slice(&self.s[start..self.i]);
            }
            Some(b'{') => {
                lv.word.expansion = true;
                let mut depth = 0usize;
                let mut j = self.i + 1;
                loop {
                    match self.s.get(j) {
                        None => return Err(Unterminated),
                        Some(b'{') => depth += 1,
                        Some(b'}') => {
                            depth -= 1;
                            if depth == 0 {
                                break;
                            }
                        }
                        Some(b'\\') => j += 1,
                        _ => {}
                    }
                    j += 1;
                }
                lv.cur.extend_from_slice(&self.s[start..=j]);
                self.i = j + 1;
            }
            Some(b'\'') if !in_dq => {
                // `$'...'`: left as written; a backslash escapes the next
                // byte, so `\'` doesn't end it.
                lv.word.ansi_c = true;
                lv.word.bare = false;
                let mut j = self.i + 2;
                loop {
                    match self.s.get(j) {
                        None => return Err(Unterminated),
                        Some(b'\\') => j += 2,
                        Some(b'\'') => break,
                        _ => j += 1,
                    }
                }
                lv.cur.extend_from_slice(&self.s[start..=j]);
                self.i = j + 1;
            }
            Some(b'"') if !in_dq => {
                // `$"..."` is a double-quoted string for the shell's purposes.
                self.i += 1;
            }
            Some(n) if n.is_ascii_alphanumeric() || b"_@*#?$!-".contains(&n) => {
                lv.word.expansion = true;
                lv.cur.push(b'$');
                self.i += 1;
            }
            _ => {
                lv.cur.push(b'$');
                self.i += 1;
            }
        }
        Ok(())
    }

    /// A backquoted substitution, the scanner on the opening backquote. Its
    /// text, with `\``, `\\` and `\$` unescaped, is tokenized as a command of
    /// its own.
    fn backquote(&mut self, lv: &mut Level) -> Result<(), Unterminated> {
        let start = self.i;
        let mut inner = Vec::new();
        let mut j = self.i + 1;
        loop {
            match self.s.get(j) {
                None => return Err(Unterminated),
                Some(b'`') => break,
                Some(b'\\') => match self.s.get(j + 1) {
                    Some(&n @ (b'`' | b'\\' | b'$')) => {
                        inner.push(n);
                        j += 2;
                    }
                    Some(&n) => {
                        inner.push(b'\\');
                        inner.push(n);
                        j += 2;
                    }
                    None => return Err(Unterminated),
                },
                Some(&c) => {
                    inner.push(c);
                    j += 1;
                }
            }
        }
        let text = String::from_utf8_lossy(&inner).into_owned();
        let parsed = tokenize(&text)?;
        lv.word.expansion = true;
        lv.out.substitutions.push(Substitution {
            span: start + 1..j,
            inner: parsed,
        });
        lv.cur.extend_from_slice(&self.s[start..=j]);
        self.i = j + 1;
        Ok(())
    }

    /// A `<<` or `<<-` operator and its delimiter word, the scanner on the
    /// first `<`. The operator becomes one word holding the operator and the
    /// delimiter as written; the lines are read at the next newline.
    fn heredoc_operator(&mut self, lv: &mut Level) {
        let start = self.i;
        self.i += 2;
        let strip_tabs = self.peek(0) == Some(b'-');
        if strip_tabs {
            self.i += 1;
        }
        while matches!(self.peek(0), Some(b' ' | b'\t')) {
            self.i += 1;
        }
        let mut delim = Vec::new();
        let mut quoted = false;
        while let Some(c) = self.peek(0) {
            match c {
                b'\'' | b'"' => {
                    quoted = true;
                    match self.s[self.i + 1..].iter().position(|&b| b == c) {
                        Some(n) => {
                            delim.extend_from_slice(&self.s[self.i + 1..self.i + 1 + n]);
                            self.i += n + 2;
                        }
                        None => {
                            // An unterminated delimiter quote: the rest is the
                            // delimiter, and nothing will match it.
                            delim.extend_from_slice(&self.s[self.i + 1..]);
                            self.i = self.s.len();
                        }
                    }
                }
                b'\\' => {
                    quoted = true;
                    if let Some(n) = self.peek(1) {
                        delim.push(n);
                    }
                    self.i += 2;
                }
                b' ' | b'\t' | b'\n' | b';' | b'&' | b'|' | b'(' | b')' | b'<' | b'>' => break,
                _ => {
                    delim.push(c);
                    self.i += 1;
                }
            }
        }
        let idx = lv.out.heredocs.len();
        lv.out.heredocs.push(HereDoc {
            delimiter: String::from_utf8_lossy(&delim).into_owned(),
            quoted,
            strip_tabs,
            body: String::new(),
            terminated: false,
        });
        lv.pending.push(idx);
        lv.words.push(Word {
            text: String::from_utf8_lossy(&self.s[start..self.i]).into_owned(),
            span: start..self.i.min(self.s.len()),
            heredoc: Some(idx),
            ..Word::default()
        });
    }

    /// Consume the lines of every pending here-document, the scanner just
    /// past a newline. Inside `$(...)` a line that is the delimiter followed
    /// by `)` also ends it, leaving the `)` to close the substitution.
    fn heredoc_lines(&mut self, lv: &mut Level, end: End) {
        for idx in std::mem::take(&mut lv.pending) {
            let strip = lv.out.heredocs[idx].strip_tabs;
            let delim = lv.out.heredocs[idx].delimiter.clone().into_bytes();
            let mut body = Vec::new();
            loop {
                if self.i >= self.s.len() {
                    break;
                }
                let rest = &self.s[self.i..];
                let len = rest.iter().position(|&b| b == b'\n').unwrap_or(rest.len());
                let mut line = &rest[..len];
                if strip {
                    while let [b'\t', tail @ ..] = line {
                        line = tail;
                    }
                }
                if line == delim.as_slice() {
                    self.i += (len + 1).min(rest.len());
                    lv.out.heredocs[idx].terminated = true;
                    break;
                }
                if end == End::Paren
                    && line.starts_with(&delim)
                    && line.get(delim.len()) == Some(&b')')
                {
                    // Leave the `)`, and what follows it, for the scanner.
                    self.i += (len - line.len()) + delim.len();
                    lv.out.heredocs[idx].terminated = true;
                    break;
                }
                body.extend_from_slice(line);
                body.push(b'\n');
                self.i += (len + 1).min(rest.len());
            }
            lv.out.heredocs[idx].body = String::from_utf8_lossy(&body).into_owned();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn words(t: &Tokenized) -> Vec<Vec<String>> {
        t.segments
            .iter()
            .map(|s| s.words.iter().map(|w| w.text.clone()).collect())
            .collect()
    }

    fn w(cmd: &str) -> Vec<Vec<String>> {
        words(&tokenize(cmd).expect("tokenizes"))
    }

    fn v(rows: &[&[&str]]) -> Vec<Vec<String>> {
        rows.iter()
            .map(|r| r.iter().map(|s| s.to_string()).collect())
            .collect()
    }

    #[test]
    fn splits_at_every_unquoted_separator() {
        assert_eq!(
            w("a 1; b 2 & c | d && e || f\ng"),
            v(&[
                &["a", "1"],
                &["b", "2"],
                &["c"],
                &["d"],
                &["e"],
                &["f"],
                &["g"]
            ])
        );
        assert_eq!(w("(a; b) c"), v(&[&["a"], &["b"], &["c"]]));
    }

    #[test]
    fn quotes_never_split() {
        assert_eq!(
            w("echo 'a; b | c' \"d & e\nf\""),
            v(&[&["echo", "a; b | c", "d & e\nf"]])
        );
        assert_eq!(w("echo a\"b\"'c'd"), v(&[&["echo", "abcd"]]));
        assert_eq!(w("echo \"\""), v(&[&["echo", ""]]));
    }

    #[test]
    fn double_quotes_escape_only_four_characters() {
        assert_eq!(
            w(r#"echo "a\"b\\c\$d\`e\nf""#),
            v(&[&["echo", "a\"b\\c$d`e\\nf"]])
        );
        assert_eq!(w(r"echo a\ b\;c"), v(&[&["echo", "a b;c"]]));
    }

    #[test]
    fn backslash_newline_joins_lines() {
        assert_eq!(w("git \\\npush"), v(&[&["git", "push"]]));
        assert_eq!(w("gi\\\nt push"), v(&[&["git", "push"]]));
        assert_eq!(w("echo \"a\\\nb\""), v(&[&["echo", "ab"]]));
        // Inside single quotes it stays.
        assert_eq!(w("echo 'a\\\nb'"), v(&[&["echo", "a\\\nb"]]));
    }

    #[test]
    fn redirections_with_ampersand_stay_one_word() {
        assert_eq!(w("git push 2>&1"), v(&[&["git", "push", "2>&1"]]));
        assert_eq!(w("cmd &>out"), v(&[&["cmd", "&>out"]]));
        assert_eq!(w("cmd >|out"), v(&[&["cmd", ">|out"]]));
    }

    #[test]
    fn records_parenthesis_groups() {
        let t = tokenize("(cd a && x); (cd b); y").unwrap();
        let groups: Vec<Vec<usize>> = t.segments.iter().map(|s| s.groups.clone()).collect();
        assert_eq!(groups, vec![vec![0], vec![0], vec![1], vec![]]);
        let t = tokenize("((a) b)").unwrap();
        let depths: Vec<usize> = t.segments.iter().map(|s| s.groups.len()).collect();
        assert_eq!(depths, vec![2, 1]);
    }

    #[test]
    fn command_substitutions_are_recorded_with_their_spans() {
        let cmd = "echo $(git push) `gh pr create` \"x$(ls)\"";
        let t = tokenize(cmd).unwrap();
        assert_eq!(t.segments.len(), 1);
        assert_eq!(t.substitutions.len(), 3);
        let spans: Vec<&str> = t
            .substitutions
            .iter()
            .map(|s| &cmd[s.span.clone()])
            .collect();
        assert_eq!(spans, vec!["git push", "gh pr create", "ls"]);
        assert_eq!(words(&t.substitutions[0].inner), v(&[&["git", "push"]]));
        assert_eq!(
            words(&t.substitutions[1].inner),
            v(&[&["gh", "pr", "create"]])
        );
        let ws = &t.segments[0].words;
        assert_eq!(ws[1].text, "$(git push)");
        assert!(ws[1].expansion && ws[2].expansion && ws[3].expansion);
        assert!(!ws[0].expansion);
    }

    #[test]
    fn nested_substitutions_and_parentheses_inside_them() {
        let t = tokenize("echo $(a $(b) (c) d)").unwrap();
        assert_eq!(t.substitutions.len(), 1);
        let inner = &t.substitutions[0].inner;
        assert_eq!(inner.substitutions.len(), 1);
        assert_eq!(words(inner), v(&[&["a", "$(b)"], &["c"], &["d"]]));
    }

    #[test]
    fn single_quotes_hide_substitutions() {
        let t = tokenize("echo '$(git push)'").unwrap();
        assert!(t.substitutions.is_empty());
        assert!(!t.segments[0].words[1].expansion);
    }

    #[test]
    fn here_documents_are_data() {
        let cmd = "git commit -m \"$(cat <<'EOF'\nIt's done; git push\n)\nEOF\n)\" && ls";
        let t = tokenize(cmd).unwrap();
        assert_eq!(
            words(&t),
            v(&[
                &[
                    "git",
                    "commit",
                    "-m",
                    "$(cat <<'EOF'\nIt's done; git push\n)\nEOF\n)"
                ],
                &["ls"]
            ])
        );
        let sub = &t.substitutions[0].inner;
        assert_eq!(sub.segments.len(), 1);
        assert_eq!(sub.heredocs.len(), 1);
        let h = &sub.heredocs[0];
        assert_eq!(h.delimiter, "EOF");
        assert!(h.quoted && h.terminated);
        assert_eq!(h.body, "It's done; git push\n)\n");
        assert_eq!(t.segments[0].words[3].dq_substitution, Some(0));
    }

    #[test]
    fn here_document_forms() {
        let t = tokenize("cat <<EOF\na $X\nEOF\necho next").unwrap();
        assert_eq!(words(&t), v(&[&["cat", "<<EOF"], &["echo", "next"]]));
        assert!(!t.heredocs[0].quoted);
        assert_eq!(t.heredocs[0].body, "a $X\n");
        let t = tokenize("cat <<-\"END\"\n\tline\n\tEND\n").unwrap();
        assert!(t.heredocs[0].quoted && t.heredocs[0].strip_tabs);
        assert_eq!(t.heredocs[0].body, "line\n");
        // The delimiter followed directly by `)` closes a substitution.
        let t = tokenize("x \"$(cat <<'EOF'\nbody\nEOF)\"").unwrap();
        assert_eq!(t.substitutions[0].inner.heredocs[0].body, "body\n");
        assert_eq!(t.segments[0].words[1].dq_substitution, Some(0));
        // `<<<` is a here-string, not a here-document.
        let t = tokenize("cat <<< 'git push'").unwrap();
        assert!(t.heredocs.is_empty());
    }

    #[test]
    fn dq_substitution_only_for_a_lone_quoted_substitution() {
        let t = tokenize("a \"$(x)\" \"y$(x)\" \"$(x)y\" $(x) \"$(x)\"z").unwrap();
        let marks: Vec<Option<usize>> = t.segments[0]
            .words
            .iter()
            .map(|w| w.dq_substitution)
            .collect();
        assert_eq!(marks, vec![None, Some(0), None, None, None, None]);
    }

    #[test]
    fn ansi_c_quoting_is_left_as_written() {
        let t = tokenize("echo $'a\\'b; c' d").unwrap();
        let ws = &t.segments[0].words;
        assert_eq!(ws[1].text, "$'a\\'b; c'");
        assert!(ws[1].ansi_c);
        assert_eq!(ws[2].text, "d");
    }

    #[test]
    fn word_flags() {
        let t = tokenize("cd ~/x \"$HOME\" ${A:-b c} plain 'q'").unwrap();
        let ws = &t.segments[0].words;
        assert!(ws[1].tilde && ws[1].bare);
        assert!(ws[2].expansion && !ws[2].bare);
        assert_eq!(ws[3].text, "${A:-b c}");
        assert!(ws[3].expansion);
        assert!(ws[4].bare && !ws[4].expansion);
        assert!(!ws[5].bare);
    }

    #[test]
    fn comments_are_skipped() {
        assert_eq!(w("ls # don't\ngit push"), v(&[&["ls"], &["git", "push"]]));
        assert_eq!(w("echo a#b"), v(&[&["echo", "a#b"]]));
    }

    #[test]
    fn unterminated_quotes_are_refused() {
        for cmd in [
            "echo 'a",
            "echo \"a",
            "echo $(a",
            "echo `a",
            "echo ${a",
            "echo $'a",
            "echo \"$(a\"",
        ] {
            assert_eq!(tokenize(cmd), Err(Unterminated), "{cmd}");
        }
    }
}
