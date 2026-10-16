//! The quote-aware tokenizer both entry points share.
//!
//! It reads a Bash command the way the shell splits it, closely enough not to
//! lose a guarded command in it, and evaluates nothing. A command becomes
//! segments: the pieces between unquoted `;`, `&`, `|`, newline, `(` and `)`
//! (PRD Definitions). Each segment holds its words after quote removal and the
//! subshell groups it sits in, so the classifier can end a `cd` when its
//! subshell closes. A parenthesis group is one; so is a pipeline element next
//! to an unquoted `|`, and an and-or list ended by `&`, which the shell runs
//! in subshells too: `cd sub | x` and `cd sub &` move nothing for later
//! segments, while `;`, `&&`, `||` and a newline carry the directory on.
//!
//! An unquoted `<` or `>` starts a redirection word, as in the shell, so
//! `push>/dev/null` is `push` and `>/dev/null`; a file-descriptor number just
//! before it stays with it (`2>&1`). The word is marked [`Word::redirect`].
//!
//! Command substitutions (`$(...)` and backquotes, outside single quotes) are
//! scanned as commands of their own, one recursion level each, and recorded
//! with their spans; the word that holds one keeps the substitution's text
//! as written, so the body reader can refuse it. A here-document's lines are
//! consumed as data at the newline that follows its operator and recorded
//! apart, never split into segments: `git commit -m "$(cat <<'EOF' ... git
//! push ... EOF)"` holds no `git push` segment, and an apostrophe on one of
//! its lines can't unbalance the outer command. With an unquoted delimiter
//! the shell still expands `$(...)` and backquotes in those lines, so those
//! are scanned as commands and recorded on the [`HereDoc`].
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
    /// The word is a plain prefix (no quote, backslash, `$` or backquote)
    /// followed by one double-quoted command substitution, as in
    /// `--body="$(...)"` or `-b"$(...)"`: the prefix's length in bytes and
    /// the index into [`Tokenized::substitutions`].
    pub dq_prefixed: Option<(usize, usize)>,
    /// Starts with an unquoted redirection operator, after an optional
    /// file-descriptor number: `>out`, `2>&1`, `&>`, `<`.
    pub redirect: bool,
}

/// The words between two unquoted separators.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Segment {
    pub words: Vec<Word>,
    /// The subshell groups enclosing the segment, outermost first: its
    /// parenthesis groups, its pipeline element when a `|` is beside it, and
    /// its and-or list when `&` ends it. Each id is unique within one
    /// [`Tokenized`], so two sibling groups at the same depth never look like
    /// one.
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
    /// With an unquoted delimiter, the `$(...)` and backquoted commands in
    /// the lines, which the shell runs; empty for a quoted one.
    pub substitutions: Vec<Tokenized>,
    /// With an unquoted delimiter, a `$(` or backquote in the lines that
    /// never closes.
    pub unterminated_substitution: bool,
}

/// A tokenized command.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Tokenized {
    pub segments: Vec<Segment>,
    pub substitutions: Vec<Substitution>,
    pub heredocs: Vec<HereDoc>,
}

/// Why a command could not be tokenized (PRD R7 case 3).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Refused {
    /// An unterminated quote, `$(...)`, `${...}` or backquote.
    Unterminated,
    /// Command substitutions nested deeper than [`MAX_DEPTH`].
    TooDeep,
}

use Refused::{TooDeep, Unterminated};

/// How deep command substitutions (`$(...)`, backquotes, and those in an
/// unquoted here-document) may nest. Each level is a recursion, and a stack
/// overflow aborts the process, which a host's `|| exit 0` would turn into a
/// silent pass; deeper input is refused instead.
pub const MAX_DEPTH: usize = 64;

/// Tokenize `cmd`. A backslash followed by a newline outside single quotes is
/// removed, joining the two lines as the shell does.
pub fn tokenize(cmd: &str) -> Result<Tokenized, Refused> {
    Scanner::new(cmd.as_bytes(), 0, 0).scan(End::Eof)
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
    /// How many command substitutions enclose the text being scanned.
    depth: usize,
}

impl<'a> Scanner<'a> {
    fn new(s: &'a [u8], i: usize, depth: usize) -> Self {
        Scanner { s, i, depth }
    }

    /// A scanner for a substitution inside this one's text, or [`TooDeep`].
    fn nested<'b>(&self, s: &'b [u8], i: usize) -> Result<Scanner<'b>, Refused> {
        if self.depth >= MAX_DEPTH {
            return Err(TooDeep);
        }
        Ok(Scanner::new(s, i, self.depth + 1))
    }
}

/// A separator between segments, as far as subshells go.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Sep {
    /// `;` or a newline.
    Seq,
    /// `&&` or `||`.
    AndOr,
    /// `|` or `|&`.
    Pipe,
    /// `&`.
    Background,
    /// A `)` closing a group, or the end of the text.
    End,
}

/// Where, at one parenthesis depth, the current pipeline element and and-or
/// list start (indexes into `Tokenized::segments`), and whether a `|` came
/// before the element.
#[derive(Clone, Copy, Default)]
struct Marks {
    element: usize,
    list: usize,
    piped: bool,
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
    /// One per open parenthesis depth, the outermost (no group) first.
    marks: Vec<Marks>,
    /// The last separator, and whether a segment was pushed since: a
    /// newline straight after `|`, `&&` or `||` continues the command.
    last_sep: Sep,
    pushed_since_sep: bool,
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
            marks: vec![Marks::default()],
            last_sep: Sep::End,
            pushed_since_sep: false,
        }
    }

    /// Put the segments from `from` on in a new subshell group at depth
    /// `depth`: inside the parenthesis groups they all share, outside any
    /// group they open themselves.
    fn subshell(&mut self, from: usize, depth: usize) {
        if from >= self.out.segments.len() {
            return;
        }
        let id = self.next_group;
        self.next_group += 1;
        for s in &mut self.out.segments[from..] {
            let at = depth.min(s.groups.len());
            s.groups.insert(at, id);
        }
    }

    /// A separator at the current depth: the pipeline element it ends runs
    /// in a subshell when a `|` is on either side of it, and the and-or list
    /// `&` ends runs in one.
    fn separator(&mut self, sep: Sep) {
        let depth = self.marks.len() - 1;
        let m = self.marks[depth];
        if m.piped || sep == Sep::Pipe {
            self.subshell(m.element, depth);
        }
        if sep == Sep::Background {
            self.subshell(m.list, depth);
        }
        let len = self.out.segments.len();
        let m = &mut self.marks[depth];
        m.element = len;
        m.piped = sep == Sep::Pipe;
        if matches!(sep, Sep::Seq | Sep::Background | Sep::End) {
            m.list = len;
        }
        self.last_sep = sep;
        self.pushed_since_sep = false;
    }

    /// The end of the text this level scans: every open depth ends.
    fn finish(&mut self) {
        while !self.marks.is_empty() {
            self.separator(Sep::End);
            self.marks.pop();
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
        // one substitution spans everything between. With a plain prefix
        // before the `"`, it is `dq_prefixed`.
        let word = &s[self.start..at];
        if word.ends_with(b")\"") && word.len() >= 5 {
            let start = self.start;
            // Substitutions are recorded as they close, in order, so one
            // ending just before this word's `)"` is the last one recorded:
            // looking only at it keeps the scan linear in the command.
            let found = self.out.substitutions.len().checked_sub(1).filter(|i| {
                let sub = &self.out.substitutions[*i];
                sub.span.end == at - 2
                    && sub.span.start >= start + 3
                    && &s[sub.span.start - 3..sub.span.start] == b"\"$("
            });
            if let Some(idx) = found {
                let len = self.out.substitutions[idx].span.start - 3 - start;
                if len == 0 {
                    w.dq_substitution = Some(idx);
                } else if !s[start..start + len].iter().any(|b| b"\"'\\$`".contains(b)) {
                    w.dq_prefixed = Some((len, idx));
                }
            }
        }
        self.words.push(w);
        self.in_word = false;
    }

    /// End the segment being built; whether it had words and was kept.
    fn end_segment(&mut self, s: &[u8], at: usize) -> bool {
        self.end_word(s, at);
        if self.words.is_empty() {
            return false;
        }
        self.out.segments.push(Segment {
            words: std::mem::take(&mut self.words),
            groups: self.groups.clone(),
        });
        self.pushed_since_sep = true;
        true
    }

    /// At an unquoted `<` or `>` at byte `at`: a redirection operator. It
    /// ends the word before it, unless that word so far is only a
    /// file-descriptor number or the operator's own first characters (`2>`,
    /// `>>`, `&>`, `<>`), and the word it is in is a redirection word.
    fn redirection(&mut self, s: &[u8], at: usize) {
        let digits = self.cur.iter().take_while(|b| b.is_ascii_digit()).count();
        let ops = &self.cur[digits..];
        let keep = self.in_word
            && self.word.bare
            && (ops.is_empty() || (self.word.redirect && ops.iter().all(|b| b"<>&|".contains(b))));
        if !keep {
            self.end_word(s, at);
        }
        self.begin(at);
        self.word.redirect = true;
    }
}

impl Scanner<'_> {
    /// The `$(...)` and backquoted commands in an unquoted-delimiter
    /// here-document's lines, where only a backslash quotes, and whether one
    /// of them never closes. Nesting too deep is refused like anywhere else.
    fn heredoc_expansions(&self, body: &[u8]) -> Result<(Vec<Tokenized>, bool), Refused> {
        let mut subs = Vec::new();
        let mut i = 0;
        while i < body.len() {
            match body[i] {
                b'\\' => i += 2,
                b'$' if body.get(i + 1) == Some(&b'(') => {
                    let mut sc = self.nested(body, i + 2)?;
                    match sc.scan(End::Paren) {
                        Ok(t) => {
                            subs.push(t);
                            i = sc.i;
                        }
                        Err(Unterminated) => return Ok((subs, true)),
                        Err(TooDeep) => return Err(TooDeep),
                    }
                }
                b'`' => {
                    let mut sc = Scanner::new(body, i, self.depth);
                    let mut lv = Level::new();
                    match sc.backquote(&mut lv) {
                        Ok(()) => {
                            subs.extend(lv.out.substitutions.into_iter().map(|s| s.inner));
                            i = sc.i;
                        }
                        Err(Unterminated) => return Ok((subs, true)),
                        Err(TooDeep) => return Err(TooDeep),
                    }
                }
                _ => i += 1,
            }
        }
        Ok((subs, false))
    }
}

impl<'a> Scanner<'a> {
    fn peek(&self, off: usize) -> Option<u8> {
        self.s.get(self.i + off).copied()
    }

    fn scan(&mut self, end: End) -> Result<Tokenized, Refused> {
        let mut lv = Level::new();
        loop {
            let Some(c) = self.peek(0) else {
                if end == End::Paren {
                    return Err(Unterminated);
                }
                lv.end_segment(self.s, self.i);
                lv.finish();
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
                    let pushed = lv.end_segment(self.s, self.i);
                    // `a |`, `a &&` or `a ||` at a line's end goes on on
                    // the next line.
                    let continued = !pushed
                        && !lv.pushed_since_sep
                        && matches!(lv.last_sep, Sep::Pipe | Sep::AndOr);
                    if !continued {
                        lv.separator(Sep::Seq);
                    }
                    self.i += 1;
                    self.heredoc_lines(&mut lv, end)?;
                }
                b'&' | b'|' | b';' => {
                    // `>&`, `<&` and `>|` continue a redirection operator,
                    // so `2>&1` stays one word; `&>` starts one.
                    let continues = lv.in_word
                        && lv.word.redirect
                        && c != b';'
                        && matches!(lv.cur.last(), Some(b'>') | Some(b'<'));
                    if continues {
                        lv.cur.push(c);
                        self.i += 1;
                    } else if c == b'&' && self.peek(1) == Some(b'>') {
                        lv.end_word(self.s, self.i);
                        lv.begin(self.i);
                        lv.word.redirect = true;
                        lv.cur.push(c);
                        self.i += 1;
                    } else {
                        let (sep, len) = match (c, self.peek(1)) {
                            (b'&', Some(b'&')) | (b'|', Some(b'|')) => (Sep::AndOr, 2),
                            (b'|', Some(b'&')) => (Sep::Pipe, 2),
                            (b'|', _) => (Sep::Pipe, 1),
                            (b'&', _) => (Sep::Background, 1),
                            _ => (Sep::Seq, 1),
                        };
                        lv.end_segment(self.s, self.i);
                        lv.separator(sep);
                        self.i += len;
                    }
                }
                b'(' => {
                    lv.end_segment(self.s, self.i);
                    lv.groups.push(lv.next_group);
                    lv.next_group += 1;
                    let len = lv.out.segments.len();
                    lv.marks.push(Marks {
                        element: len,
                        list: len,
                        piped: false,
                    });
                    self.i += 1;
                }
                b')' => {
                    lv.end_segment(self.s, self.i);
                    self.i += 1;
                    if lv.groups.is_empty() {
                        if end == End::Paren {
                            lv.finish();
                            return Ok(lv.out);
                        }
                        // A stray `)`, as after a `case` pattern.
                        lv.separator(Sep::End);
                    } else {
                        lv.separator(Sep::End);
                        lv.groups.pop();
                        lv.marks.pop();
                    }
                }
                b'<' if self.peek(1) == Some(b'<') => {
                    if self.peek(2) == Some(b'<') {
                        // `<<<`, a here-string: a redirection word.
                        lv.redirection(self.s, self.i);
                        lv.cur.extend_from_slice(b"<<<");
                        self.i += 3;
                    } else {
                        lv.end_word(self.s, self.i);
                        self.heredoc_operator(&mut lv);
                    }
                }
                b'<' | b'>' => {
                    lv.redirection(self.s, self.i);
                    lv.cur.push(c);
                    self.i += 1;
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
    fn double_quoted(&mut self, lv: &mut Level) -> Result<(), Refused> {
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
    fn dollar(&mut self, lv: &mut Level, in_dq: bool) -> Result<(), Refused> {
        let start = self.i;
        match self.peek(1) {
            Some(b'(') => {
                lv.word.expansion = true;
                self.i += 2;
                let inner_start = self.i;
                let mut sc = self.nested(self.s, self.i)?;
                let inner = sc.scan(End::Paren)?;
                self.i = sc.i;
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
    fn backquote(&mut self, lv: &mut Level) -> Result<(), Refused> {
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
        let parsed = self.nested(text.as_bytes(), 0)?.scan(End::Eof)?;
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
                    // A command ending in `<<\` has nothing to escape.
                    self.i = (self.i + 2).min(self.s.len());
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
            substitutions: Vec::new(),
            unterminated_substitution: false,
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
    fn heredoc_lines(&mut self, lv: &mut Level, end: End) -> Result<(), Refused> {
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
            if !lv.out.heredocs[idx].quoted {
                let (subs, unterminated) = self.heredoc_expansions(&body)?;
                lv.out.heredocs[idx].substitutions = subs;
                lv.out.heredocs[idx].unterminated_substitution = unterminated;
            }
            lv.out.heredocs[idx].body = String::from_utf8_lossy(&body).into_owned();
        }
        Ok(())
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
    fn an_unquoted_angle_bracket_starts_a_redirection_word() {
        assert_eq!(
            w("git push>/dev/null"),
            v(&[&["git", "push", ">/dev/null"]])
        );
        assert_eq!(w("a 2>x"), v(&[&["a", "2>x"]]));
        // A digit is a file descriptor only when it is the whole word so far.
        assert_eq!(w("a2>x"), v(&[&["a2", ">x"]]));
        assert_eq!(w("x&>out"), v(&[&["x", "&>out"]]));
        assert_eq!(w("a>b>c"), v(&[&["a", ">b", ">c"]]));
        assert_eq!(w("a>>b <c"), v(&[&["a", ">>b", "<c"]]));
        assert_eq!(w("\"a\">b"), v(&[&["a", ">b"]]));
        assert_eq!(w("cat<<<x"), v(&[&["cat", "<<<x"]]));
        assert_eq!(w("a 2>&1|b"), v(&[&["a", "2>&1"], &["b"]]));
        let t = tokenize("echo '>' \\> > out 2>&1").unwrap();
        let marks: Vec<bool> = t.segments[0].words.iter().map(|w| w.redirect).collect();
        assert_eq!(marks, vec![false, false, false, true, false, true]);
        // Quoted, it is text; inside a word's quotes it never splits.
        assert_eq!(w("echo 'a>b' \"c<d\""), v(&[&["echo", "a>b", "c<d"]]));
    }

    #[test]
    fn many_quoted_substitutions_tokenize_in_linear_time() {
        // About 4 MiB of words, each one quoted substitution.
        let cmd = "x \"$(a)\" -b\"$(b)\" ".repeat(200_000);
        let start = std::time::Instant::now();
        let t = tokenize(&cmd).unwrap();
        let took = start.elapsed();
        assert_eq!(t.substitutions.len(), 400_000);
        let ws = &t.segments[0].words;
        assert_eq!(ws[1].dq_substitution, Some(0));
        assert_eq!(ws[2].dq_prefixed, Some((2, 1)));
        assert_eq!(ws.last().unwrap().dq_prefixed, Some((2, 399_999)));
        assert!(took < std::time::Duration::from_secs(10), "took {took:?}");
    }

    #[test]
    fn substitutions_nested_too_deep_are_refused() {
        let deep = |n: usize| format!("git push {}x{}", "$(".repeat(n), ")".repeat(n));
        assert!(tokenize(&deep(MAX_DEPTH)).is_ok());
        assert_eq!(tokenize(&deep(MAX_DEPTH + 1)), Err(Refused::TooDeep));
        assert_eq!(tokenize(&deep(5000)), Err(Refused::TooDeep));
        // Unclosed, deep nesting is refused before the end is reached.
        assert_eq!(tokenize(&"$(".repeat(5000)), Err(Refused::TooDeep));
        let quoted = format!("echo \"{}\"", "$(".repeat(5000));
        assert_eq!(tokenize(&quoted), Err(Refused::TooDeep));
        // Inside an unquoted here-document too.
        let heredoc = format!("cat <<EOF\n{}\nEOF", "$(".repeat(5000));
        assert_eq!(tokenize(&heredoc), Err(Refused::TooDeep));
        // Backquotes nest through escaping; a few levels are fine.
        assert!(tokenize("echo `a \\`b\\``").is_ok());
    }

    #[test]
    fn a_plain_prefix_before_a_quoted_substitution_is_recorded() {
        let t = tokenize("gh --body=\"$(cat x)\" -b\"$(cat y)\" -b=\"$(z)\" a\"$(x)\" \"$(x)\"")
            .unwrap();
        let marks: Vec<(Option<(usize, usize)>, Option<usize>)> = t.segments[0]
            .words
            .iter()
            .map(|w| (w.dq_prefixed, w.dq_substitution))
            .collect();
        assert_eq!(
            marks,
            vec![
                (None, None),
                (Some((7, 0)), None),
                (Some((2, 1)), None),
                (Some((3, 2)), None),
                (Some((1, 3)), None),
                (None, Some(4)),
            ]
        );
        // A quote, `$` or backslash in the prefix, or text after, isn't one.
        let t = tokenize("'-b'\"$(x)\" $a\"$(x)\" -b\"$(x)\"z").unwrap();
        assert!(t.segments[0].words.iter().all(|w| w.dq_prefixed.is_none()));
    }

    #[test]
    fn a_command_ending_in_a_here_document_backslash_tokenizes() {
        let t = tokenize("cat <<\\").unwrap();
        assert_eq!(words(&t), v(&[&["cat", "<<\\"]]));
        assert!(t.heredocs[0].quoted);
        assert!(tokenize("cat <<").is_ok());
        assert!(tokenize("cat <<-\\").is_ok());
    }

    #[test]
    fn pipeline_elements_and_background_lists_are_subshell_groups() {
        let groups = |cmd: &str| -> Vec<Vec<usize>> {
            tokenize(cmd)
                .unwrap()
                .segments
                .iter()
                .map(|s| s.groups.clone())
                .collect()
        };
        // `;`, `&&`, `||` and newlines make no group.
        assert_eq!(groups("cd a; b && c || d\ne"), vec![Vec::<usize>::new(); 5]);
        // Each element of a pipeline gets one.
        assert_eq!(groups("cd a | b; c"), vec![vec![0], vec![1], vec![]]);
        assert_eq!(groups("a | cd b && c"), vec![vec![0], vec![1], vec![]]);
        assert_eq!(groups("a |& b"), vec![vec![0], vec![1]]);
        // A pipe at a line's end carries on to the next line.
        assert_eq!(groups("a |\ncd b\nc"), vec![vec![0], vec![1], vec![]]);
        // An and-or list `&` ends gets one around all of it.
        assert_eq!(groups("cd a & b"), vec![vec![0], vec![]]);
        assert_eq!(groups("cd a && b & c"), vec![vec![0], vec![0], vec![]]);
        // Inside the parenthesis groups it sits in, outside the ones it opens.
        assert_eq!(
            groups("(cd a | b); c"),
            vec![vec![0, 1], vec![0, 2], vec![]]
        );
        assert_eq!(groups("cd a && (b) & c"), vec![vec![1], vec![1, 0], vec![]]);
        // `2>&1` and `&>` are no separators.
        assert_eq!(groups("cd a 2>&1 &>x; b"), vec![Vec::<usize>::new(); 2]);
    }

    #[test]
    fn an_unquoted_here_document_records_its_command_substitutions() {
        let t = tokenize("cat <<EOF\nIt's $(git push) and `gh pr create`\n\\$(no)\nEOF").unwrap();
        let h = &t.heredocs[0];
        assert!(!h.quoted && !h.unterminated_substitution);
        let subs: Vec<Vec<Vec<String>>> = h.substitutions.iter().map(words).collect();
        assert_eq!(
            subs,
            vec![v(&[&["git", "push"]]), v(&[&["gh", "pr", "create"]])]
        );
        // A quoted delimiter keeps the lines pure data.
        let t = tokenize("cat <<'EOF'\n$(git push)\nEOF").unwrap();
        assert!(t.heredocs[0].substitutions.is_empty());
        let t = tokenize("cat <<EOF\n$(git push\nEOF").unwrap();
        assert!(t.heredocs[0].unterminated_substitution);
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
            assert_eq!(tokenize(cmd), Err(Refused::Unterminated), "{cmd}");
        }
    }
}
