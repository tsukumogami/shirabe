//! The command classifier: which segments are guarded, and which can't be
//! checked (PRD Definitions, R2, R4's "which repository", R7 cases 9 to 11).
//!
//! It walks a tokenized command's segments in order. For each it skips the
//! leading `NAME=value`, redirection and reserved words, takes the head by its
//! last path component, drops the redirection words that follow it (and a
//! bare operator's target), and returns a guarded segment as [`GhSegment`] or
//! [`PushSegment`] with the directory it runs in. A guarded segment it can't
//! check becomes a [`FailClosed`] case instead: an unlisted global option, a
//! `GIT_...=` assignment on a push, a wrapped guarded command (a wrapper head,
//! a `$` head, or a guarded segment inside a command substitution), an
//! earlier segment that changes what a push sends, or a push in a directory
//! it can't follow. The body-file check against earlier segments needs the
//! body reader's path, so it is [`Classified::earlier_names_file`].
//!
//! The directory starts at the input's `cwd` and moves through `cd` and
//! `pushd` with one literal argument; `cd` with none, `-` or a non-literal
//! one, or a `popd`, makes it unknown. A `cd` inside parentheses ends when the
//! group closes, as in a subshell, and so does one in a pipeline element
//! (`cd sub | x`) or in an and-or list ended by `&`: the tokenizer gives
//! those a group of their own.

use std::path::{Component, Path, PathBuf};

use super::reason::{Action, Case, FailClosed, PrAction};
use super::tokenize::{HereDoc, Segment, Tokenized, Word};

/// Heads that run another command (PRD Definitions, wrapped guarded command).
const WRAPPERS: &[&str] = &[
    "env", "command", "builtin", "exec", "eval", "bash", "sh", "zsh", "dash", "xargs", "sudo",
    "time", "nohup", "timeout", "nice", "ssh", "docker", "podman", "mise", "nix", "python",
    "python3", "perl", "ruby", "node",
];

/// Words skipped before a segment's head.
const RESERVED: &[&str] = &[
    "if", "then", "elif", "else", "do", "while", "until", "!", "{", "}",
];

/// `git` subcommands an earlier segment may run before a push in the same
/// command: none changes what the push would send, except `fetch`, which can
/// only shrink it (PRD R7 case 11).
const READ_ONLY_GIT: &[&str] = &[
    "status",
    "log",
    "diff",
    "show",
    "add",
    "rev-parse",
    "describe",
    "ls-files",
    "grep",
    "blame",
    "fetch",
];

/// A guarded `gh pr create|edit` segment.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GhSegment {
    pub action: PrAction,
    /// The words after the action word.
    pub words: Vec<Word>,
    /// The directory it runs in; `None` when unknown.
    pub dir: Option<PathBuf>,
    /// Its index in the command's top-level segments.
    pub index: usize,
}

/// A guarded `git push` segment, for the push check.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PushSegment {
    /// The words after `push`, with their quoting, so the push check can
    /// refuse one the shell would expand.
    pub words: Vec<Word>,
    /// The directory it runs in, `-C` paths applied.
    pub dir: PathBuf,
    pub index: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Item {
    Gh(GhSegment),
    Push(PushSegment),
    Fail(FailClosed),
}

/// The classifier's answer.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Classified {
    pub items: Vec<Item>,
    /// Each top-level segment's words and the directory it runs in, for the
    /// earlier-segment check on a body file.
    segments: Vec<(Vec<Word>, Option<PathBuf>)>,
}

/// What the coarse "named in the text" test finds (PRD Definitions).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Named {
    pub pr: bool,
    pub push: bool,
}

impl Named {
    /// The actions it names, PR first.
    pub fn actions(self) -> Vec<Action> {
        let mut v = Vec::new();
        if self.pr {
            v.push(Action::Pr(None));
        }
        if self.push {
            v.push(Action::Push);
        }
        v
    }
}

/// The coarse test: with its `"` and `'` characters dropped (the shell
/// removes quotes without splitting, so `g"i"t` is `git`), lowercased and
/// split into words of `[a-z0-9_-]`, the text has `gh`, later `pr`, later
/// `create` or `edit`; or `git`, later `push`. Every other character only
/// separates words.
pub fn named_in_text(text: &str) -> Named {
    let lower: String = text
        .chars()
        .filter(|c| *c != '"' && *c != '\'')
        .map(|c| c.to_ascii_lowercase())
        .collect();
    let toks: Vec<&str> = lower
        .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '-'))
        .filter(|t| !t.is_empty())
        .collect();
    let after = |from: usize, want: &[&str]| -> Option<usize> {
        toks[from..]
            .iter()
            .position(|t| want.contains(t))
            .map(|i| from + i)
    };
    let pr = after(0, &["gh"])
        .and_then(|g| after(g + 1, &["pr"]))
        .and_then(|p| after(p + 1, &["create", "edit"]))
        .is_some();
    let push = after(0, &["git"])
        .and_then(|g| after(g + 1, &["push"]))
        .is_some();
    Named { pr, push }
}

/// The coarse test on the raw hook input, its JSON escapes `\n`, `\r`, `\t`,
/// `\"` and `\\` decoded and a backslash-newline removed (the shell joins the
/// two lines), the way the plugin's script reads it.
pub fn named_in_raw_input(raw: &str) -> Named {
    let mut out = String::with_capacity(raw.len());
    let mut chars = raw.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some('t') => out.push('\t'),
            Some('"') => out.push('"'),
            Some('\\') => out.push('\\'),
            Some(o) => {
                out.push('\\');
                out.push(o);
            }
            None => out.push('\\'),
        }
    }
    named_in_text(&out.replace("\\\n", ""))
}

/// How a segment reads once its leading words are skipped.
enum Kind {
    /// Nothing guarded.
    Other,
    /// `cd` or `pushd`, with its arguments.
    Cd(Vec<Word>),
    Popd,
    /// `gh [-R x] pr create|edit`, with the first unlisted global option.
    Gh {
        action: PrAction,
        rest: Vec<Word>,
        bad_option: Option<String>,
    },
    /// `git` with its subcommand (`None` for a bare `git`).
    Git {
        sub: Option<String>,
        rest: Vec<Word>,
        c_dirs: Vec<Word>,
        bad_option: Option<String>,
        /// The first leading `GIT_...` assignment.
        git_assignment: Option<String>,
    },
    /// A wrapper head or a `$` head, and what its text names.
    Wrapper {
        head: String,
        named: Named,
    },
}

fn is_assignment(t: &str) -> bool {
    match t.split_once('=') {
        Some((name, _)) => {
            name.chars()
                .next()
                .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
                && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
        }
        None => false,
    }
}

/// A redirection word, and whether its target is the next word (`>`, `2>`,
/// `>>`, `<`, `&>`, `<<<` alone).
fn redirection(w: &Word) -> Option<bool> {
    if w.heredoc.is_some() {
        return Some(false);
    }
    if !w.redirect {
        return None;
    }
    let t = w.text.as_str();
    let rest = t.trim_start_matches(|c: char| c.is_ascii_digit());
    let op_len = ["<<<", "&>>", "&>", ">>", ">&", "<&", ">|", "<>", ">", "<"]
        .iter()
        .find(|op| rest.starts_with(*op))
        .map(|op| op.len())?;
    Some(rest.len() == op_len)
}

/// `ws` without its redirection words and the target word after a bare
/// operator, wherever they stand: `git push origin topic 2>&1` pushes
/// `origin topic`, and `cd sub 2>/dev/null` moves to `sub`.
fn without_redirections(ws: &[Word]) -> Vec<Word> {
    let mut out = Vec::with_capacity(ws.len());
    let mut i = 0;
    while i < ws.len() {
        match redirection(&ws[i]) {
            Some(true) => i += 2,
            Some(false) => i += 1,
            None => {
                out.push(ws[i].clone());
                i += 1;
            }
        }
    }
    out
}

fn basename(t: &str) -> &str {
    t.rsplit('/').next().unwrap_or(t)
}

/// Skip `gh` options from `ws[from]`: `-R <v>`, `--repo <v>` and
/// `--repo=<v>` are understood, any other `-` word is the first unlisted
/// option. Returns the next position, that option, and whether the last word
/// skipped was an unlisted option without `=`, which may have taken the next
/// word as its value.
fn gh_options(ws: &[Word], from: usize) -> (usize, Option<String>, bool) {
    let mut j = from;
    let mut bad = None;
    let mut ambiguous = false;
    while let Some(w) = ws.get(j) {
        let t = w.text.as_str();
        if t == "-R" || t == "--repo" {
            ambiguous = false;
            j += 2;
        } else if t.starts_with("--repo=") {
            ambiguous = false;
            j += 1;
        } else if t.starts_with('-') {
            bad.get_or_insert_with(|| t.to_string());
            ambiguous = !t.contains('=');
            j += 1;
        } else {
            break;
        }
    }
    (j, bad, ambiguous)
}

/// The positions the next word may be at: `j`, and `j + 1` when an unlisted
/// option just before it may have taken `ws[j]` as its value. A match at
/// `j + 1` always carries that option, so it fails closed.
fn candidates(j: usize, ambiguous: bool) -> Vec<usize> {
    if ambiguous {
        vec![j, j + 1]
    } else {
        vec![j]
    }
}

fn kind(seg: &Segment) -> Kind {
    let ws = &seg.words;
    let mut i = 0;
    let mut git_assignment = None;
    while i < ws.len() {
        let t = ws[i].text.as_str();
        if is_assignment(t) {
            if t.starts_with("GIT_") && git_assignment.is_none() {
                git_assignment = Some(t.split('=').next().unwrap_or(t).to_string() + "=");
            }
            i += 1;
        } else if let Some(takes_next) = redirection(&ws[i]) {
            i += if takes_next { 2 } else { 1 };
        } else if ws[i].bare && RESERVED.contains(&t) {
            i += 1;
        } else {
            break;
        }
    }
    let Some(head) = ws.get(i) else {
        return Kind::Other;
    };
    let args = without_redirections(&ws[i + 1..]);
    let rest = args.as_slice();
    let text_of = |ws: &[Word]| {
        ws.iter()
            .map(|w| w.text.as_str())
            .collect::<Vec<_>>()
            .join(" ")
    };
    if head.text.starts_with('$') {
        let later: Vec<&str> = rest.iter().map(|w| w.text.as_str()).collect();
        let push = later.contains(&"push");
        let pr = later
            .windows(2)
            .any(|p| p[0] == "pr" && (p[1] == "create" || p[1] == "edit"));
        return Kind::Wrapper {
            head: head.text.clone(),
            named: Named { pr, push },
        };
    }
    let name = basename(&head.text);
    if WRAPPERS.contains(&name) {
        return Kind::Wrapper {
            head: head.text.clone(),
            named: named_in_text(&text_of(&ws[i..])),
        };
    }
    match name {
        "cd" | "pushd" => Kind::Cd(rest.to_vec()),
        "popd" => Kind::Popd,
        "gh" => {
            // gh takes `-R`/`--repo` before `pr` or between `pr` and the
            // action word, so both runs of options are skipped.
            let (j, mut bad_option, ambiguous) = gh_options(rest, 0);
            for p in candidates(j, ambiguous) {
                if rest.get(p).map(|w| w.text.as_str()) != Some("pr") {
                    continue;
                }
                let (k, bad2, ambiguous2) = gh_options(rest, p + 1);
                for a in candidates(k, ambiguous2) {
                    let action = match rest.get(a).map(|w| w.text.as_str()) {
                        Some("create") => PrAction::Create,
                        Some("edit") => PrAction::Edit,
                        _ => continue,
                    };
                    bad_option = bad_option.or(bad2);
                    return Kind::Gh {
                        action,
                        rest: rest[a + 1..].to_vec(),
                        bad_option,
                    };
                }
            }
            Kind::Other
        }
        "git" => {
            let mut j = 0;
            let mut bad_option = None;
            let mut ambiguous = false;
            let mut c_dirs = Vec::new();
            while j < rest.len() {
                let t = rest[j].text.as_str();
                match t {
                    "-C" => {
                        if let Some(w) = rest.get(j + 1) {
                            c_dirs.push(w.clone());
                        }
                        ambiguous = false;
                        j += 2;
                    }
                    "-c" => {
                        ambiguous = false;
                        j += 2;
                    }
                    "--no-pager" | "-P" => {
                        ambiguous = false;
                        j += 1;
                    }
                    _ if t.starts_with('-') => {
                        bad_option.get_or_insert_with(|| t.to_string());
                        ambiguous = !t.contains('=');
                        j += 1;
                    }
                    _ => break,
                }
            }
            // `git --git-dir /x push`: the unknown option may have taken the
            // next word as its value, so `push` one word later counts too,
            // and fails closed on the option.
            if ambiguous
                && rest.get(j).map(|w| w.text.as_str()) != Some("push")
                && rest.get(j + 1).map(|w| w.text.as_str()) == Some("push")
            {
                j += 1;
            }
            Kind::Git {
                sub: rest.get(j).map(|w| w.text.clone()),
                rest: rest.get(j + 1..).map(<[Word]>::to_vec).unwrap_or_default(),
                c_dirs,
                bad_option,
                git_assignment,
            }
        }
        _ => Kind::Other,
    }
}

/// A word the directory can follow: literal, not `-`, not `~...`.
fn literal(w: &Word) -> bool {
    !w.expansion && !w.ansi_c && !w.tilde && !w.text.is_empty() && w.text != "-"
}

/// `p` with `.` and `..` removed lexically, as `cd` does by default.
pub(crate) fn normalize(p: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for c in p.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// `dir` moved to the word `w`, or `None` when that can't be followed.
fn moved(dir: Option<&Path>, w: &Word) -> Option<PathBuf> {
    if !literal(w) {
        return None;
    }
    let p = Path::new(&w.text);
    if p.is_absolute() {
        Some(normalize(p))
    } else {
        dir.map(|d| normalize(&d.join(p)))
    }
}

impl std::ops::BitOrAssign for Named {
    fn bitor_assign(&mut self, other: Named) {
        self.pr |= other.pr;
        self.push |= other.push;
    }
}

/// Whether `tok` (a command substitution's contents) holds a guarded or a
/// wrapped guarded segment, and what it names.
fn holds_guarded(tok: &Tokenized) -> Named {
    let mut named = Named::default();
    for seg in &tok.segments {
        match kind(seg) {
            Kind::Gh { .. } => named.pr = true,
            Kind::Git { sub, .. } if sub.as_deref() == Some("push") => named.push = true,
            Kind::Wrapper { named: n, .. } => named |= n,
            _ => {}
        }
    }
    for sub in &tok.substitutions {
        named |= holds_guarded(&sub.inner);
    }
    for h in &tok.heredocs {
        named |= heredoc_runs(h);
    }
    named
}

/// What the commands an unquoted-delimiter here-document's lines run name:
/// the shell expands `$(...)` and backquotes there, so a guarded segment in
/// one is a wrapped guarded command. A substitution that never closes can't
/// be split, so the coarse test reads the lines instead. A quoted delimiter
/// leaves the lines data, and names nothing.
fn heredoc_runs(h: &HereDoc) -> Named {
    let mut named = Named::default();
    for sub in &h.substitutions {
        named |= holds_guarded(sub);
    }
    if h.unterminated_substitution {
        named |= named_in_text(&h.body);
    }
    named
}

/// Classify a tokenized command run from `cwd`.
pub fn classify(tok: &Tokenized, cwd: Option<&Path>) -> Classified {
    let mut c = Classified::default();
    let mut dir: Option<PathBuf> = cwd.filter(|p| p.is_absolute()).map(normalize);
    let mut stack: Vec<(usize, Option<PathBuf>)> = Vec::new();
    // Why the directory became unknown, for the deny.
    let mut lost = String::from("the hook input gives no absolute `cwd`");
    // Heads of earlier segments that rule out a later push, first one kept.
    let mut push_blocker: Option<String> = None;

    for (index, seg) in tok.segments.iter().enumerate() {
        // Leave the groups this segment isn't in, restoring the directory each
        // had on entry; then enter the new ones.
        while let Some((g, _)) = stack.last() {
            if seg.groups.contains(g) {
                break;
            }
            dir = stack.pop().and_then(|(_, d)| d);
        }
        for g in &seg.groups {
            if !stack.iter().any(|(s, _)| s == g) {
                stack.push((*g, dir.clone()));
            }
        }
        c.segments.push((seg.words.clone(), dir.clone()));

        match kind(seg) {
            Kind::Other => {}
            Kind::Cd(args) => {
                let to = match args.as_slice() {
                    [w] => moved(dir.as_deref(), w),
                    _ => None,
                };
                if to.is_none() {
                    lost = format!(
                        "an earlier `{}` moves to a directory the hook can't follow (no argument, `-`, or not a literal path)",
                        seg.words.iter().map(|w| w.text.as_str()).collect::<Vec<_>>().join(" ")
                    );
                }
                dir = to;
            }
            Kind::Popd => {
                lost = "an earlier `popd` moves to a directory the hook can't follow".into();
                dir = None;
            }
            Kind::Wrapper { head, named } => {
                for action in named.actions() {
                    c.items.push(Item::Fail(FailClosed {
                        action,
                        case: Case::Wrapped,
                    }));
                }
                push_blocker.get_or_insert(head);
            }
            Kind::Gh {
                action,
                rest,
                bad_option,
            } => {
                let a = Action::Pr(Some(action));
                if let Some(opt) = bad_option {
                    c.items.push(Item::Fail(FailClosed {
                        action: a,
                        case: Case::UnknownOption(opt),
                    }));
                } else {
                    c.items.push(Item::Gh(GhSegment {
                        action,
                        words: rest,
                        dir: dir.clone(),
                        index,
                    }));
                }
            }
            Kind::Git {
                sub,
                rest,
                c_dirs,
                bad_option,
                git_assignment,
            } => {
                if sub.as_deref() != Some("push") {
                    if let Some(s) = &sub {
                        if !READ_ONLY_GIT.contains(&s.as_str()) {
                            push_blocker.get_or_insert_with(|| format!("git {s}"));
                        }
                    }
                    continue;
                }
                let fail = |case| {
                    Item::Fail(FailClosed {
                        action: Action::Push,
                        case,
                    })
                };
                if let Some(opt) = git_assignment.or(bad_option) {
                    c.items.push(fail(Case::UnknownOption(opt)));
                    continue;
                }
                if let Some(head) = &push_blocker {
                    c.items.push(fail(Case::SameCommand(format!(
                        "an earlier `{head}` in the same command could change what the push sends, and the hook checks before it runs"
                    ))));
                    continue;
                }
                let mut at = dir.clone();
                let mut why = lost.clone();
                for w in &c_dirs {
                    at = moved(at.as_deref(), w);
                    if at.is_none() {
                        why = format!("`git -C {}` isn't a literal path", w.text);
                        break;
                    }
                }
                match at {
                    Some(d) => c.items.push(Item::Push(PushSegment {
                        words: rest,
                        dir: d,
                        index,
                    })),
                    None => c.items.push(fail(Case::Directory(why))),
                }
                // A push changes the remote-tracking refs a later push reads.
                push_blocker.get_or_insert_with(|| "git push".into());
            }
        }
    }

    // A guarded or wrapped guarded segment inside a command substitution,
    // anywhere in the command, unquoted here-documents included, is a
    // wrapped guarded command.
    let nested = tok
        .substitutions
        .iter()
        .map(|sub| holds_guarded(&sub.inner))
        .chain(tok.heredocs.iter().map(heredoc_runs));
    for named in nested {
        for action in named.actions() {
            c.items.push(Item::Fail(FailClosed {
                action,
                case: Case::Wrapped,
            }));
        }
    }
    c
}

impl Classified {
    /// Whether a top-level segment before `index` names the body file `file`
    /// (absolute) given as `given`: the same word, a word resolving to the
    /// same path from that segment's directory, or a word ending in the
    /// file's name, alone or after `>` or `>>` (PRD R7 case 11).
    pub fn earlier_names_file(&self, index: usize, file: &Path, given: &str) -> bool {
        let name = file.file_name().map(|n| n.to_string_lossy().into_owned());
        self.segments[..index.min(self.segments.len())]
            .iter()
            .any(|(words, dir)| {
                words.iter().any(|w| {
                    let t = w
                        .text
                        .trim_start_matches(|c: char| c.is_ascii_digit())
                        .trim_start_matches('&')
                        .trim_start_matches('>');
                    if t.is_empty() {
                        return false;
                    }
                    t == given
                        || name.as_deref().is_some_and(|n| t.ends_with(n))
                        || moved(
                            dir.as_deref(),
                            &Word {
                                text: t.to_string(),
                                ..w.clone()
                            },
                        )
                        .is_some_and(|p| p == file)
                })
            })
    }
}

#[cfg(test)]
mod tests {
    use super::super::tokenize::tokenize;
    use super::*;

    const CWD: &str = "/work/repo";

    fn cl(cmd: &str) -> Classified {
        classify(&tokenize(cmd).expect("tokenizes"), Some(Path::new(CWD)))
    }

    fn fails(cmd: &str) -> Vec<(Action, Case)> {
        cl(cmd)
            .items
            .into_iter()
            .filter_map(|i| match i {
                Item::Fail(f) => Some((f.action, f.case)),
                _ => None,
            })
            .collect()
    }

    fn pushes(cmd: &str) -> Vec<PushSegment> {
        cl(cmd)
            .items
            .into_iter()
            .filter_map(|i| match i {
                Item::Push(p) => Some(p),
                _ => None,
            })
            .collect()
    }

    fn ghs(cmd: &str) -> Vec<GhSegment> {
        cl(cmd)
            .items
            .into_iter()
            .filter_map(|i| match i {
                Item::Gh(g) => Some(g),
                _ => None,
            })
            .collect()
    }

    // --- the example table, row by row ------------------------------------

    #[test]
    fn unguarded_rows_give_nothing() {
        for cmd in [
            "ls",
            "git status",
            "git commit -m x",
            "gh pr view 3",
            "echo \"gh pr create\"",
            "gh issue create --title pr --body edit",
            "git log --grep push",
        ] {
            assert_eq!(cl(cmd).items, vec![], "{cmd}");
        }
    }

    #[test]
    fn wrapped_rows_fail_closed() {
        for cmd in [
            "sudo git push",
            "env X=1 git push",
            "bash -c \"git push\"",
            "eval \"git push\"",
            "$GIT push",
            "echo $(git push)",
        ] {
            assert_eq!(fails(cmd), vec![(Action::Push, Case::Wrapped)], "{cmd}");
            assert!(pushes(cmd).is_empty(), "{cmd}");
        }
        assert_eq!(
            fails("echo `gh pr create`"),
            vec![(Action::Pr(None), Case::Wrapped)]
        );
        assert_eq!(
            fails("bash -c 'gh pr create --title x --body y'"),
            vec![(Action::Pr(None), Case::Wrapped)]
        );
        assert_eq!(
            fails("$G pr edit 3 --title x"),
            vec![(Action::Pr(None), Case::Wrapped)]
        );
        // A wrapper whose text names nothing guarded is just a command.
        assert_eq!(cl("sudo ls").items, vec![]);
        assert_eq!(cl("$EDITOR file").items, vec![]);
        // Nested substitutions are found too.
        assert_eq!(
            fails("echo \"$(echo $(git push))\""),
            vec![(Action::Push, Case::Wrapped)]
        );
    }

    #[test]
    fn a_here_document_inside_a_substitution_is_data() {
        let cmd = "git commit -m \"$(cat <<'EOF'\nthen git push\nEOF\n)\"";
        assert_eq!(cl(cmd).items, vec![]);
        // Unquoted, its plain lines are data too.
        let cmd = "git commit -m \"$(cat <<EOF\nthen git push\nEOF\n)\"";
        assert_eq!(cl(cmd).items, vec![]);
    }

    #[test]
    fn a_substitution_in_an_unquoted_here_document_is_wrapped() {
        for cmd in [
            "cat <<EOF\nIt's $(git push) now\nEOF",
            "cat <<EOF\n`git push`\nEOF",
            "git commit -m \"$(cat <<EOF\nmsg $(git push)\nEOF\n)\"",
            "cat <<EOF\n$(echo x; sudo git push)\nEOF",
            "cat <<EOF\n$(git push\nEOF",
        ] {
            assert_eq!(fails(cmd), vec![(Action::Push, Case::Wrapped)], "{cmd}");
        }
        assert_eq!(
            fails("cat <<-END\n\t$(gh pr create --title x)\n\tEND"),
            vec![(Action::Pr(None), Case::Wrapped)]
        );
        // A quoted delimiter, or an escaped `$`, keeps the lines data.
        for cmd in [
            "cat <<'EOF'\n$(git push)\nEOF",
            "cat <<\"EOF\"\n`git push`\nEOF",
            "cat <<\\EOF\n$(git push)\nEOF",
            "cat <<EOF\n\\$(git push)\nEOF",
            "cat <<EOF\n$(date) git push\nEOF",
        ] {
            assert_eq!(cl(cmd).items, vec![], "{cmd}");
        }
    }

    #[test]
    fn redirection_words_are_no_arguments() {
        let texts = |p: &PushSegment| p.words.iter().map(|w| w.text.clone()).collect::<Vec<_>>();
        for (cmd, want) in [
            (
                "git push -u origin feature 2>&1",
                vec!["-u", "origin", "feature"],
            ),
            ("git push origin HEAD >/dev/null", vec!["origin", "HEAD"]),
            ("git push origin topic > log", vec!["origin", "topic"]),
            ("git push origin 2> err topic", vec!["origin", "topic"]),
            (
                "git push >>log origin <in topic &>x",
                vec!["origin", "topic"],
            ),
            ("git 2>/dev/null push origin", vec!["origin"]),
            ("git push>/dev/null", vec![]),
            ("git push<<<x", vec![]),
            ("git push<<EOF\nbody\nEOF", vec![]),
        ] {
            let p = pushes(cmd);
            assert_eq!(p.len(), 1, "{cmd}");
            assert_eq!(texts(&p[0]), want, "{cmd}");
            assert_eq!(fails(cmd), vec![], "{cmd}");
        }
        // A quoted `>` is an argument.
        assert_eq!(
            texts(&pushes("git push origin '>' x")[0]),
            vec!["origin", ">", "x"]
        );
        assert_eq!(
            pushes("cd sub 2>/dev/null && git push")[0].dir,
            PathBuf::from("/work/repo/sub")
        );
        assert_eq!(
            pushes("cd >/dev/null sub && git push")[0].dir,
            PathBuf::from("/work/repo/sub")
        );
        let g = ghs("gh pr create --title x 2>&1 --body y >out");
        let words: Vec<&str> = g[0].words.iter().map(|w| w.text.as_str()).collect();
        assert_eq!(words, vec!["--title", "x", "--body", "y"]);
        assert_eq!(ghs("gh pr create>/dev/null").len(), 1);
        assert_eq!(ghs("gh 2>&1 pr edit 3").len(), 1);
    }

    #[test]
    fn a_cd_in_a_pipeline_or_a_background_list_moves_nothing_after_it() {
        for cmd in [
            "cd sub | cat; git push",
            "cd sub & git push",
            "ls | cd sub && git push",
            "cd sub && ls & git push",
            "cd sub |\ncat\ngit push",
            "pushd sub | cat; git push",
        ] {
            assert_eq!(pushes(cmd)[0].dir, PathBuf::from(CWD), "{cmd}");
        }
        for cmd in ["popd | cat; git push", "cd \"$X\" & git push"] {
            assert_eq!(pushes(cmd)[0].dir, PathBuf::from(CWD), "{cmd}");
            assert_eq!(fails(cmd), vec![], "{cmd}");
        }
        // `;`, `&&`, `||` and newlines carry it on.
        for cmd in [
            "cd sub; git push",
            "cd sub && git push",
            "cd sub || git push",
            "cd sub\ngit push",
            "cd sub && git push &",
        ] {
            assert_eq!(pushes(cmd)[0].dir, PathBuf::from("/work/repo/sub"), "{cmd}");
        }
    }

    #[test]
    fn heads_compare_by_basename_after_skipped_words() {
        assert_eq!(pushes("/usr/bin/git push").len(), 1);
        assert_eq!(pushes("if true; then git push; fi").len(), 1);
        assert_eq!(pushes("2>&1 git push").len(), 1);
        assert_eq!(pushes("> out git push").len(), 1);
        assert_eq!(pushes("! git push").len(), 1);
        assert_eq!(pushes("{ git push; }").len(), 1);
        let g = ghs("GH_TOKEN=t gh -R o/r pr create --title x");
        assert_eq!(g.len(), 1);
        assert_eq!(g[0].action, PrAction::Create);
        assert_eq!(g[0].words[0].text, "--title");
        assert_eq!(ghs("gh --repo o/r pr edit 3").len(), 1);
        assert_eq!(ghs("gh --repo=o/r pr edit 3").len(), 1);
        // gh also takes `-R` between `pr` and the action word.
        for cmd in [
            "gh pr -R o/r create --title x",
            "gh pr --repo o/r create --title x",
            "gh pr --repo=o/r edit 3",
            "gh -R a/b pr -R o/r edit 3",
        ] {
            let g = ghs(cmd);
            assert_eq!(g.len(), 1, "{cmd}");
            assert_eq!(fails(cmd), vec![], "{cmd}");
        }
        assert_eq!(cl("gh pr -R o/r view 3").items, vec![]);
        assert_eq!(ghs("/opt/bin/gh pr create").len(), 1);
    }

    #[test]
    fn earlier_segments_that_change_a_push_fail_closed() {
        for cmd in [
            "git commit -m x && git push",
            "git checkout other && git push",
            "sudo ls; git push",
            "$X; git push",
            "git push origin a; git push origin b",
        ] {
            let f = fails(cmd);
            assert!(
                f.iter()
                    .any(|(a, c)| *a == Action::Push && matches!(c, Case::SameCommand(_))),
                "{cmd}: {f:?}"
            );
        }
        for cmd in [
            "git status && git push",
            "git add . && git push",
            "git fetch && git log && git push",
            "ls && git push",
        ] {
            assert_eq!(fails(cmd), vec![], "{cmd}");
            assert_eq!(pushes(cmd).len(), 1, "{cmd}");
        }
    }

    #[test]
    fn push_words_and_directory() {
        let p = pushes("git push --force origin +topic");
        let texts = |p: &PushSegment| p.words.iter().map(|w| w.text.clone()).collect::<Vec<_>>();
        assert_eq!(texts(&p[0]), vec!["--force", "origin", "+topic"]);
        assert_eq!(p[0].dir, PathBuf::from(CWD));
        assert_eq!(pushes("git push origin --delete topic")[0].words.len(), 3);
        assert_eq!(
            texts(&pushes("git push origin :topic")[0]),
            vec!["origin", ":topic"]
        );
        assert_eq!(pushes("git -c k=v push").len(), 1);
        assert_eq!(pushes("git --no-pager -P push").len(), 1);
        assert_eq!(
            pushes("cd sub && git push")[0].dir,
            PathBuf::from("/work/repo/sub")
        );
        assert_eq!(
            pushes("git -C sub push")[0].dir,
            PathBuf::from("/work/repo/sub")
        );
        assert_eq!(
            pushes("cd sub && git -C ../other push")[0].dir,
            PathBuf::from("/work/repo/other")
        );
        assert_eq!(
            pushes("pushd /abs && git push")[0].dir,
            PathBuf::from("/abs")
        );
        assert_eq!(
            pushes("(cd sub && ls); git push")[0].dir,
            PathBuf::from(CWD)
        );
        assert_eq!(pushes("(cd a); (git push)")[0].dir, PathBuf::from(CWD));
        assert_eq!(
            pushes("(cd sub; git push)")[0].dir,
            PathBuf::from("/work/repo/sub")
        );
        assert_eq!(
            pushes("cd sub\ngit push")[0].dir,
            PathBuf::from("/work/repo/sub")
        );
    }

    #[test]
    fn an_unknown_directory_fails_closed() {
        for cmd in [
            "cd \"$DIR\" && git push",
            "cd && git push",
            "cd - && git push",
            "pushd \"$X\" && git push",
            "popd && git push",
            "cd ~/x && git push",
            "git -C \"$P\" push",
            "cd a b && git push",
        ] {
            let f = fails(cmd);
            assert!(
                matches!(f.as_slice(), [(Action::Push, Case::Directory(_))]),
                "{cmd}: {f:?}"
            );
        }
        // No cwd at all.
        let c = classify(&tokenize("git push").unwrap(), None);
        assert!(matches!(
            c.items.as_slice(),
            [Item::Fail(FailClosed {
                case: Case::Directory(_),
                ..
            })]
        ));
        // An absolute `cd` recovers it.
        let c = classify(&tokenize("cd /r && git push").unwrap(), None);
        assert!(matches!(c.items.as_slice(), [Item::Push(_)]));
    }

    #[test]
    fn unlisted_global_options_fail_closed() {
        assert_eq!(
            fails("git --git-dir=/x push"),
            vec![(Action::Push, Case::UnknownOption("--git-dir=/x".into()))]
        );
        assert_eq!(
            fails("GIT_DIR=/x git push"),
            vec![(Action::Push, Case::UnknownOption("GIT_DIR=".into()))]
        );
        // An unlisted option may take the next word as its value, so the
        // guarded word one later counts too.
        assert_eq!(
            fails("gh --hostname h pr create --title x"),
            vec![(
                Action::Pr(Some(PrAction::Create)),
                Case::UnknownOption("--hostname".into())
            )]
        );
        assert_eq!(
            fails("gh pr --hostname h edit 3"),
            vec![(
                Action::Pr(Some(PrAction::Edit)),
                Case::UnknownOption("--hostname".into())
            )]
        );
        for opt in ["--git-dir /x", "--work-tree w", "--namespace n"] {
            let cmd = format!("git {opt} push");
            let name = opt.split(' ').next().unwrap();
            assert_eq!(
                fails(&cmd),
                vec![(Action::Push, Case::UnknownOption(name.into()))],
                "{cmd}"
            );
        }
        assert_eq!(
            fails("gh --verbose pr create"),
            vec![(
                Action::Pr(Some(PrAction::Create)),
                Case::UnknownOption("--verbose".into())
            )]
        );
        // Not guarded: options don't matter.
        assert_eq!(fails("GIT_DIR=/x git status"), vec![]);
        assert_eq!(fails("git --bare log"), vec![]);
    }

    #[test]
    fn earlier_segments_naming_the_body_file() {
        let c = cl("printf 'x' > b.md && gh pr create --title t -F b.md");
        let g = ghs("printf 'x' > b.md && gh pr create --title t -F b.md");
        let file = Path::new("/work/repo/b.md");
        assert!(c.earlier_names_file(g[0].index, file, "b.md"));
        let c = cl("echo x >>sub/../b.md; gh pr create");
        assert!(c.earlier_names_file(1, file, "b.md"));
        let c = cl("cd sub && cp x ../b.md && gh pr create");
        assert!(c.earlier_names_file(2, file, "b.md"));
        let c = cl("ls && gh pr create --title t -F b.md");
        assert!(!c.earlier_names_file(1, file, "b.md"));
        assert!(!c.earlier_names_file(0, file, "b.md"));
    }

    #[test]
    fn the_coarse_test() {
        let yes = [
            (
                "gh pr create",
                Named {
                    pr: true,
                    push: false,
                },
            ),
            (
                "GH PR EDIT",
                Named {
                    pr: true,
                    push: false,
                },
            ),
            (
                "echo \"git push\"",
                Named {
                    pr: false,
                    push: true,
                },
            ),
            (
                "gh x pr y create",
                Named {
                    pr: true,
                    push: false,
                },
            ),
            (
                "git -C a push",
                Named {
                    pr: false,
                    push: true,
                },
            ),
        ];
        for (t, n) in yes {
            assert_eq!(named_in_text(t), n, "{t}");
        }
        for t in [
            "ls",
            "gh pr view",
            "git pushx",
            "github pr create",
            "push git",
            "git-push",
        ] {
            assert_eq!(named_in_text(t), Named::default(), "{t}");
        }
        assert!(named_in_raw_input(r#"{"command":"cd repo\ngit push"}"#).push);
        // A backslash-newline joins the lines with nothing between them.
        assert!(!named_in_raw_input("cd x\\\ngit push").push);
        assert!(named_in_raw_input(r#"{"command":"gi\\\nt push"}"#).push);
        assert!(named_in_raw_input(r#"{"command":"git \\\npush"}"#).push);
        assert!(!named_in_raw_input(r#"{"command":"echo a\\ngit"}"#).push);
        // Quotes are dropped, not read as separators.
        assert!(named_in_text("g\"i\"t pu'sh'").push);
        assert!(named_in_raw_input(r#"{"command":"g\"i\"t push"}"#).push);
        assert_eq!(
            named_in_text("echo \"gh\"\"pr\"\"create\""),
            Named::default()
        );
    }

    /// This side of the table both coarse tests answer: every row of
    /// `hooks/testdata/coarse-cases.tsv` gets its expected answer from
    /// `named_in_raw_input`. hooks/pre-action-deny_test.sh runs the plugin
    /// script's side. The rows are JSON string values, escapes included, so
    /// they go into the document as written.
    #[test]
    fn named_in_raw_input_answers_coarse_cases_tsv() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../hooks/testdata/coarse-cases.tsv");
        let table = std::fs::read_to_string(&path).expect("coarse-cases.tsv");
        let mut rows = 0;
        for line in table.lines() {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let (want, command) = line.split_once('\t').expect("answer, tab, command");
            let input = format!(r#"{{"tool_name":"Bash","tool_input":{{"command":"{command}"}}}}"#);
            let named = named_in_raw_input(&input);
            let got = if named.pr || named.push {
                "named"
            } else {
                "clear"
            };
            assert_eq!(got, want, "{command}");
            rows += 1;
        }
        assert!(rows > 0, "no rows in {}", path.display());
    }
}
