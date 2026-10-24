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
//! A head names a program in any case: on a case-insensitive filesystem,
//! macOS's default, the shell's PATH lookup finds `/usr/bin/env` for `ENV`
//! and gh for `GH`, and it folds Unicode case too (`ſudo` finds sudo), so
//! the last path component is folded ([`fold`]) before it is compared with
//! `gh`, `git` and [`WRAPPERS`]. The shell matches a builtin or keyword by
//! its exact name, so `EVAL` or `TIME` isn't the builtin; the wrappers among
//! them are folded anyway, since reading one as a wrapper only denies more. `cd`, `pushd` and `popd` are the exception, because
//! there the error runs the other way: `CD sub` runs a `cd` program in a
//! child process that moves nothing, and reading it as `cd` would check a
//! later push in the wrong directory. The words after the head keep their
//! case, since gh and git read their subcommands exactly (`gh PR create` is
//! an unknown command).
//!
//! An `env` head is judged by the command it runs when that command is `gh`:
//! past env's own options and assignment operands, it is classified the way it
//! would be unwrapped, so `env -u GH_TOKEN gh pr merge --body "a new path"` is a
//! merge, not a create. A guarded command found there, or named in env's own
//! option and assignment words (which gh may run), still makes the `env`
//! segment a wrapped guarded command. Every other wrapper, and an `env` whose
//! arguments the hook can't read or whose command is anything but `gh`
//! (`env_command`), is judged by the coarse test on its text.
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

/// Heads that run another command (PRD Definitions, wrapped guarded command),
/// in lowercase: a head matches one in any case.
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
    /// Where each top-level segment's text ends.
    ends: Vec<usize>,
    /// The command substitutions at the top level, unquoted here-documents'
    /// included, each run before any segment that ends after it starts.
    nested: Vec<Nested>,
}

/// What a command substitution's segments, at any depth, do to a guarded
/// segment after it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct Nested {
    /// Where it starts in the command: the substitution's own text, or a
    /// here-document's `<<` operator.
    start: usize,
    /// The first head in it that rules out a later push.
    blocker: Option<String>,
    /// Every word in it, for the body-file check.
    words: Vec<Word>,
    /// The directory of the top-level segment it sits in.
    dir: Option<PathBuf>,
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
/// `create`, `new` (gh's alias for `create`) or `edit`; or `git`, later
/// `push`. Every other character only
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
        .and_then(|p| after(p + 1, &["create", "new", "edit"]))
        .is_some();
    let push = after(0, &["git"])
        .and_then(|g| after(g + 1, &["push"]))
        .is_some();
    Named { pr, push }
}

/// The coarse test on a command's text, a backslash-newline removed first as
/// the shell joins the two lines, the way [`named_in_raw_input`] reads it.
pub fn named_in_command(command: &str) -> Named {
    named_in_text(&command.replace("\\\n", ""))
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
    named_in_command(&out)
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
    /// A wrapper head or a `$` or backquote head, and the guarded actions it
    /// runs. For an `env` that runs `gh`, that is what the gh command names
    /// plus what env's own words name to the text test; otherwise what the
    /// segment's text names.
    Wrapper {
        head: String,
        named: Named,
    },
    /// A command other than `git` that changes what a later push sends:
    /// `gh pr checkout` (`co`) switches the branch.
    ChangesPush(String),
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

/// A head's name folded the way a case-insensitive filesystem compares it.
/// macOS folds Unicode case in full, not only ASCII: `ſh` (long s) finds
/// `/bin/sh`, `ßh` finds `ssh` and the ligature `ﬆat` finds `stat`. Each
/// character is uppercased and then lowercased, which covers those (and the
/// Kelvin sign's `k`); it also folds a few the filesystem keeps apart, such
/// as dotless `ı` to `i`, which only makes the hook check more.
fn fold(name: &str) -> String {
    name.chars()
        .flat_map(char::to_uppercase)
        .flat_map(char::to_lowercase)
        .collect()
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

/// Where the command an `env` runs starts in its arguments `ws`, redirections
/// already dropped: past the options `-i`, `-`, `--ignore-environment`, `-0`,
/// `--null`, `-v`, `--debug`, `-u NAME`, `-uNAME`, `--unset NAME`,
/// `--unset=NAME` and `--`, then past the operands holding a `=`, when that
/// command is `gh`.
///
/// env takes every operand with a `=` in it as an assignment, not only a
/// shell `NAME=value` (`a-b=1`, `'X Y=1'`, `=1`), so all of them are skipped:
/// read as the command, `a-b=1 gh pr create` would be an unguarded program.
///
/// `None` when the hook can't tell, and the caller falls back to the text
/// test over the whole segment: any other option (`-S` splits a string into a
/// command, `-C` changes directory, and an option the hook doesn't know may
/// take a value); a word before the command, or the command word itself, that
/// the shell expands, since an unquoted `$X` can split into more words; no
/// command at all; or a command other than `gh`.
///
/// That last one covers a lot. An unlisted launcher (`stdbuf`, `arch`,
/// `ksh -c`) would read as an unguarded program; `gh` itself matches in any
/// case, as a head does, so `GH` is read as gh. `git` reads a subcommand by
/// its name, so `git -c 'alias.p=!git push' p` names no push. And a listed
/// wrapper, `env` included, can join env's words with its own: with
/// `env 'BASH_FUNC_f%%=() { gh "$@"; }' bash -c 'f pr create'` env's words
/// hold only `gh` and bash's only `pr create`, so only the text test over both
/// sees the create. A head `kind_words` learns to guard later falls back here
/// until it is added, which is the safe direction.
///
/// The option arms run in order: the exact `-u`/`--unset` (which take the next
/// word) before the `-u` prefix (`-uNAME`), and both before the arm for any
/// other word starting with `-`, which gives up.
fn env_command(ws: &[Word]) -> Option<usize> {
    let plain = |w: &Word| !w.expansion && !w.ansi_c;
    let mut j = 0;
    while let Some(w) = ws.get(j) {
        if !plain(w) {
            return None;
        }
        match w.text.as_str() {
            "--" => {
                j += 1;
                break;
            }
            "-i" | "-" | "--ignore-environment" | "-0" | "--null" | "-v" | "--debug" => j += 1,
            "-u" | "--unset" => {
                if !ws.get(j + 1).is_some_and(plain) {
                    return None;
                }
                j += 2;
            }
            t if t.starts_with("--unset=") || t.starts_with("-u") => j += 1,
            t if t.starts_with('-') => return None,
            _ => break,
        }
    }
    while let Some(w) = ws.get(j) {
        if !w.text.contains('=') {
            break;
        }
        if !plain(w) {
            return None;
        }
        j += 1;
    }
    ws.get(j)
        // Folded, as `kind_words` compares a head, so the two agree on `GH`.
        .is_some_and(|w| plain(w) && fold(basename(&w.text)) == "gh")
        .then_some(j)
}

/// What a segment of kind `k` names: a guarded `gh` or `git push`, or a
/// wrapper whose own reading named one.
fn named_by(k: &Kind) -> Named {
    match k {
        Kind::Gh { .. } => Named {
            pr: true,
            push: false,
        },
        Kind::Git { sub, .. } if sub.as_deref() == Some("push") => Named {
            pr: false,
            push: true,
        },
        Kind::Wrapper { named, .. } => *named,
        _ => Named::default(),
    }
}

fn kind(seg: &Segment) -> Kind {
    kind_words(&seg.words)
}

/// [`kind`] on a segment's words, or on the `gh` command an `env` runs.
fn kind_words(ws: &[Word]) -> Kind {
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
    // A head the shell computes: `$GIT`, `$(which git)`, `` `which git` ``.
    if head.text.starts_with('$') || head.text.starts_with('`') {
        let later: Vec<&str> = rest.iter().map(|w| w.text.as_str()).collect();
        let push = later.contains(&"push");
        let pr = later
            .windows(2)
            .any(|p| p[0] == "pr" && matches!(p[1], "create" | "new" | "edit"));
        return Kind::Wrapper {
            head: head.text.clone(),
            named: Named { pr, push },
        };
    }
    // A head matches in any case (the module docs say why), so `name` is the
    // folded basename. `exact` keeps the spelling as written, for the
    // builtins below that match only that way. `env_command` makes the same
    // comparison for the `gh` an env runs.
    let exact = basename(&head.text);
    let folded = fold(exact);
    let name = folded.as_str();
    if WRAPPERS.contains(&name) {
        // `env` (on WRAPPERS, which is what brings it here) runs the command
        // after its own options and assignments. When that command is `gh`,
        // gh's own reading decides what it runs, as it would unwrapped: a
        // merge body saying "new", or an issue title naming `gh pr create`, is
        // an argument, not a guarded command. Any other command, a wrapper or
        // a nested `env` included, gets the text test over the whole segment
        // (`env_command` says why). The other wrappers take a shell string
        // (`bash -c`, `eval`, `ssh`) or an option grammar of their own
        // (`sudo -u`, `timeout 5`, `xargs`) that can hide one, so their text
        // decides.
        let gh_at = if name == "env" {
            env_command(rest)
        } else {
            None
        };
        let named = match gh_at {
            // env's own words still get the text test, apart from gh's: an
            // assignment can carry a command gh runs (`GH_BROWSER`,
            // `GH_EDITOR`). A merge body comes after `gh`, so it isn't among
            // them. gh is never a wrapper, so nothing joins the two halves.
            Some(j) => {
                let mut named = named_in_text(&text_of(&rest[..j]));
                named |= named_by(&kind_words(&rest[j..]));
                named
            }
            None => named_in_text(&text_of(&ws[i..])),
        };
        return Kind::Wrapper {
            head: head.text.clone(),
            named,
        };
    }
    match name {
        // Builtins, which the shell finds only as written: `CD sub` runs a
        // `cd` program in a child that moves nothing, so it falls to `Other`
        // and the directory stays put. Without the guard a later push would
        // be checked in a directory the shell never moved to.
        "cd" | "pushd" if exact == name => Kind::Cd(rest.to_vec()),
        "popd" if exact == name => Kind::Popd,
        "gh" => {
            // gh takes `-R`/`--repo` before `pr` or between `pr` and the
            // action word, so both runs of options are skipped.
            let (j, bad1, ambiguous) = gh_options(rest, 0);
            let word = |p: usize| rest.get(p).map(|w| w.text.as_str());
            // `new` is gh's built-in alias for `create`.
            let action_at = |p: usize| match word(p) {
                Some("create" | "new") => Some(PrAction::Create),
                Some("edit") => Some(PrAction::Edit),
                _ => None,
            };
            for p in candidates(j, ambiguous) {
                if word(p) != Some("pr") {
                    continue;
                }
                let (k, bad2, ambiguous2) = gh_options(rest, p + 1);
                for a in candidates(k, ambiguous2) {
                    if let Some(sub @ ("checkout" | "co")) = word(a) {
                        return Kind::ChangesPush(format!("gh pr {sub}"));
                    }
                    let Some(action) = action_at(a) else {
                        continue;
                    };
                    return Kind::Gh {
                        action,
                        rest: rest[a + 1..].to_vec(),
                        bad_option: bad1.or(bad2),
                    };
                }
            }
            // An unlisted option may take any number of words as its value,
            // so after one, any later `pr` and any later action word after
            // it count, and fail closed on the option.
            let pr_at = if bad1.is_some() {
                (j..rest.len()).find(|p| word(*p) == Some("pr"))
            } else {
                Some(j).filter(|p| word(*p) == Some("pr"))
            };
            if let Some(p) = pr_at {
                let (_, bad2, _) = gh_options(rest, p + 1);
                if let Some(bad) = bad1.or(bad2) {
                    if let Some((a, action)) =
                        (p + 1..rest.len()).find_map(|a| action_at(a).map(|act| (a, act)))
                    {
                        return Kind::Gh {
                            action,
                            rest: rest[a + 1..].to_vec(),
                            bad_option: Some(bad),
                        };
                    }
                }
            }
            Kind::Other
        }
        "git" => {
            let mut j = 0;
            let mut bad_option = None;
            let mut c_dirs = Vec::new();
            while j < rest.len() {
                let t = rest[j].text.as_str();
                match t {
                    "-C" => {
                        if let Some(w) = rest.get(j + 1) {
                            c_dirs.push(w.clone());
                        }
                        j += 2;
                    }
                    "-c" => j += 2,
                    "--no-pager" | "-P" => j += 1,
                    _ if t.starts_with('-') => {
                        bad_option.get_or_insert_with(|| t.to_string());
                        j += 1;
                    }
                    _ => break,
                }
            }
            // `git --git-dir /x --work-tree . push`: an unknown option may
            // take any number of words as its value, so after one, any later
            // `push` counts, and fails closed on the option.
            if bad_option.is_some() && rest.get(j).map(|w| w.text.as_str()) != Some("push") {
                if let Some(p) = (j..rest.len()).find(|p| rest[*p].text == "push") {
                    j = p;
                }
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
        named |= named_by(&kind(seg));
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

/// The head of a segment that rules out a later push in the same command: a
/// wrapper or computed head, a `git` subcommand that isn't read-only, or a
/// command such as `gh pr checkout` that switches the branch (PRD R7 case
/// 11).
fn push_blocker_of(k: &Kind) -> Option<String> {
    match k {
        Kind::Wrapper { head, .. } => Some(head.clone()),
        Kind::ChangesPush(what) => Some(what.clone()),
        Kind::Git { sub: Some(s), .. } if !READ_ONLY_GIT.contains(&s.as_str()) => {
            Some(format!("git {s}"))
        }
        _ => None,
    }
}

/// Gather what `tok`, a command substitution's contents, does, its own
/// substitutions and unquoted here-documents' included.
fn nested_effects(tok: &Tokenized, out: &mut Nested) {
    for seg in &tok.segments {
        out.words.extend(seg.words.iter().cloned());
        if out.blocker.is_none() {
            out.blocker = push_blocker_of(&kind(seg));
        }
    }
    for sub in &tok.substitutions {
        nested_effects(&sub.inner, out);
    }
    for h in &tok.heredocs {
        for t in &h.substitutions {
            nested_effects(t, out);
        }
    }
}

/// The top-level substitutions of `tok`, unquoted here-documents' included,
/// with where each starts and what it does.
fn nested_in(tok: &Tokenized) -> Vec<Nested> {
    let mut out = Vec::new();
    for sub in &tok.substitutions {
        let mut n = Nested {
            start: sub.span.start,
            ..Nested::default()
        };
        nested_effects(&sub.inner, &mut n);
        out.push(n);
    }
    for seg in &tok.segments {
        for w in &seg.words {
            let Some(h) = w.heredoc.and_then(|i| tok.heredocs.get(i)) else {
                continue;
            };
            for t in &h.substitutions {
                let mut n = Nested {
                    start: w.span.start,
                    ..Nested::default()
                };
                nested_effects(t, &mut n);
                out.push(n);
            }
        }
    }
    out.sort_by_key(|n| n.start);
    out
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
    // Command substitutions run before the segment they sit in, so one that
    // starts before a guarded segment ends is an earlier part of the command.
    c.nested = nested_in(tok);

    for (index, seg) in tok.segments.iter().enumerate() {
        let seg_end = seg.words.last().map_or(0, |w| w.span.end);
        c.ends.push(seg_end);
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
            Kind::ChangesPush(what) => {
                push_blocker.get_or_insert(what);
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
                // Asked for the first push only: every later one has the
                // earlier push as its blocker.
                let in_substitution = c
                    .nested
                    .iter()
                    .take_while(|n| n.start < seg_end)
                    .find_map(|n| n.blocker.clone());
                if let Some(head) = in_substitution {
                    c.items.push(fail(Case::SameCommand(format!(
                        "a `{head}` in a command substitution that runs before the push could change what it sends, and the hook checks before either runs"
                    ))));
                    push_blocker = Some(head);
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
    // Each substitution runs in the directory of the segment it sits in. Both
    // lists are in text order, so one pass pairs them.
    let mut at = 0;
    for n in &mut c.nested {
        while at < c.ends.len() && c.ends[at] <= n.start {
            at += 1;
        }
        n.dir = c.segments.get(at).and_then(|s| s.1.clone());
    }
    c
}

impl Classified {
    /// Whether a part of the command run before top-level segment `index`
    /// names the body file `file` (absolute) given as `given`: a word of an
    /// earlier segment, or of a command substitution starting before that
    /// segment ends, that is the same word, resolves to the same path from
    /// its directory, or ends in the file's name, alone or after `>` or `>>`
    /// (PRD R7 case 11).
    pub fn earlier_names_file(&self, index: usize, file: &Path, given: &str) -> bool {
        let name = file.file_name().map(|n| n.to_string_lossy().into_owned());
        let names = |words: &[Word], dir: &Option<PathBuf>| {
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
        };
        let end = self.ends.get(index).copied().unwrap_or(usize::MAX);
        self.segments[..index.min(self.segments.len())]
            .iter()
            .any(|(words, dir)| names(words, dir))
            || self
                .nested
                .iter()
                .any(|n| n.start < end && names(&n.words, &n.dir))
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
    fn env_runs_the_command_after_its_options() {
        for cmd in [
            "env -u GH_TOKEN gh pr merge 123 -R o/r --squash --subject \"fix: x\" --body \"Adds a new edit path.\"",
            "env GH_TOKEN= gh pr merge 1 --squash --body \"creates a new thing\"",
            "env -i PATH=/usr/bin gh pr merge 1 --body new",
            "env --unset=GH_TOKEN gh pr merge 1 --body edit",
            "env --unset GH_TOKEN -- gh pr merge 1 --body create",
            "env -uGH_TOKEN -v gh pr merge 1 --body new",
            "env - gh pr merge 1 --body new",
            "env 2>/dev/null -u GH_TOKEN gh pr merge 1 --body new",
            "env -u GH_TOKEN gh issue create --title \"hook refuses gh pr create\" --body x",
            "env a-b=1 'X Y=1' =1 gh pr merge 1 --body new",
            // The body comes after the command, so the text test on env's
            // own words never sees it.
            "env -u GH_TOKEN gh pr merge 1 --squash --body \"Adds a new path\"",
            "env",
            "env -i",
        ] {
            assert_eq!(cl(cmd).items, vec![], "{cmd}");
        }
    }

    #[test]
    fn a_merge_body_or_a_quoted_title_naming_create_is_no_create() {
        for cmd in [
            "gh pr merge 123 -R o/r --squash --body \"Adds a new edit path.\"",
            "GH_TOKEN= gh pr merge 1 --body \"gh pr create\"",
            "gh issue create --title \"hook refuses gh pr create\" --body \"gh pr edit\"",
        ] {
            assert_eq!(cl(cmd).items, vec![], "{cmd}");
        }
    }

    #[test]
    fn env_wrapped_guarded_commands_stay_wrapped() {
        let wrapped = [(Action::Pr(None), Case::Wrapped)];
        for cmd in [
            "env -u GH_TOKEN gh pr create --title \"feat: x\" --body \"Adds x.\"",
            "env GH_TOKEN= gh pr edit 12 --body x",
            "env -- gh pr new -t x",
            "env -i gh -R o/r pr create",
            "env env -u X gh pr create",
            "env -u X sudo gh pr create",
            "env $GH pr create",
            "env -S \"gh pr create\"",
            "env -C /tmp gh pr create",
            // env takes any operand with a `=` as an assignment.
            "env a-b=1 gh pr create --title x --body y",
            "env 'X Y=1' gh pr create --title x --body y",
            "env =1 gh pr create --title x --body y",
            // A program other than gh falls back.
            "env stdbuf -oL gh pr create",
            "env arch -arm64 gh pr create",
            "env ksh -c 'gh pr create --title x'",
            "env gh/ pr create",
            // An option after an assignment is the command; `-u` takes `--`
            // as its name, as GNU env does.
            "env A=1 -u X gh pr create",
            "env -u -- gh pr create",
            // An assignment can carry a command the program after it runs,
            // so env's own words are text-tested too.
            "env 'BASH_FUNC_f%%=() { gh pr create --title x --body y; }' bash -c f",
            "env 'PS4=$(gh pr create)' bash -xc true",
            "env 'GH_BROWSER=sh -c \"gh pr create --fill\"' gh pr view 1 --web",
            // A wrapper after env can join env's words with its own, so the
            // whole segment is text-tested.
            "env 'BASH_FUNC_f%%=() { gh \"$@\"; }' bash -c 'f pr create'",
        ] {
            assert_eq!(fails(cmd), wrapped, "{cmd}");
            assert!(ghs(cmd).is_empty(), "{cmd}");
        }
        // A push behind env stays wrapped: git there, like any program but
        // gh, gets the text test over the whole segment, since an alias can
        // hide a push from the subcommand reading.
        for cmd in [
            "env -u X git push",
            "env GIT_DIR=/x git push",
            "env -- git -C sub push",
            "env 'X Y=1' git push",
            "env a-b=1 git push",
            "env caffeinate git push",
            "env git -c 'alias.p=!git push' p",
            "env 'BASH_FUNC_f%%=() { git push; }' bash -c f",
            "env 'BASH_FUNC_f%%=() { git \"$@\"; }' bash -c 'f push'",
        ] {
            assert_eq!(fails(cmd), vec![(Action::Push, Case::Wrapped)], "{cmd}");
            assert!(pushes(cmd).is_empty(), "{cmd}");
        }
    }

    #[test]
    fn an_env_the_hook_cannot_read_falls_back_to_the_text_test() {
        // An unlisted option, or an expansion before the command, may hide
        // what env runs, so the text decides, as it does for other wrappers.
        let wrapped = [(Action::Pr(None), Case::Wrapped)];
        for cmd in [
            "env -C /tmp gh pr merge 1 --body \"a new path\"",
            "env -u \"$X\" gh pr merge 1 --body new",
            "env A=$X gh pr merge 1 --body new",
            // Only gh is read past env; any other program's quoted arguments,
            // a nested env's included, go to the text test.
            "env -u GH_TOKEN koto next w --with-data '{\"note\": \"gh pr edit\"}'",
            "env env -u GH_TOKEN gh pr merge 1 --body new",
            // env's own words are text-tested, so an assignment whose value
            // names a guarded action is denied, whatever gh then runs.
            "env NOTE='gh pr create' gh pr merge 1",
        ] {
            assert_eq!(fails(cmd), wrapped, "{cmd}");
        }
        // `-u` with no name falls back, and the text test finds nothing
        // guarded in `env -u`.
        assert_eq!(cl("env -u").items, vec![]);
    }

    #[test]
    fn a_wrapper_head_matches_in_any_case() {
        // On a case-insensitive filesystem `ENV` runs env and `Sudo` runs
        // sudo, so each is read as its lowercase spelling (#1074).
        let wrapped = [(Action::Pr(None), Case::Wrapped)];
        for cmd in [
            "ENV gh pr create -t \"feat: x\" -b \"Adds x.\"",
            "Env gh pr create -t x",
            "ENV -u GH_TOKEN gh pr create --title x --body y",
            "eNV --unset=GH_TOKEN -- gh pr new -t x",
            "ENV GH_TOKEN= gh pr edit 12 --body x",
            "/USR/BIN/ENV gh pr create",
            "ENV SUDO gh pr create",
            "SUDO gh pr create",
            "Sudo -u x gh pr edit 3 --body y",
            "BASH -c 'gh pr create --title x'",
            "Bash -c \"gh pr edit 3\"",
            "XARGS gh pr create",
            "EVAL 'gh pr create'",
        ] {
            assert_eq!(fails(cmd), wrapped, "{cmd}");
            assert!(ghs(cmd).is_empty(), "{cmd}");
        }
        let capitalized = |w: &str| w[..1].to_ascii_uppercase() + &w[1..];
        for w in WRAPPERS {
            for head in [w.to_ascii_uppercase(), capitalized(w)] {
                let cmd = format!("{head} git push");
                assert_eq!(fails(&cmd), vec![(Action::Push, Case::Wrapped)], "{cmd}");
                assert!(pushes(&cmd).is_empty(), "{cmd}");
                let cmd = format!("{head} gh pr create --title x");
                assert_eq!(fails(&cmd), wrapped, "{cmd}");
                // A wrapper naming nothing guarded is still just a command,
                // and still rules out a later push.
                assert_eq!(cl(&format!("{head} ls")).items, vec![], "{head}");
                assert!(same_command(&format!("{head} ls && git push")), "{head}");
            }
        }
        // `ENV` reads the gh command it runs as `env` does.
        for cmd in [
            "ENV -u GH_TOKEN gh pr merge 1 --squash --body \"Adds a new edit path.\"",
            "Env GH_TOKEN= gh pr merge 1 --squash --body \"creates a new thing\"",
            "ENV -u GH_TOKEN gh issue create --title \"hook refuses gh pr create\" --body x",
        ] {
            assert_eq!(cl(cmd).items, vec![], "{cmd}");
        }
    }

    #[test]
    fn a_guarded_head_matches_in_any_case() {
        // `GH` runs gh and `GIT` runs git on a case-insensitive filesystem,
        // so each is checked as gh or git, not left unguarded.
        for (cmd, action) in [
            ("GH pr create --title x", PrAction::Create),
            ("Gh -R o/r pr new -t x", PrAction::Create),
            ("/OPT/BIN/GH pr edit 3 --body y", PrAction::Edit),
            ("GH_TOKEN=t GH pr --repo o/r edit 3", PrAction::Edit),
        ] {
            let g = ghs(cmd);
            assert_eq!(g.len(), 1, "{cmd}");
            assert_eq!(g[0].action, action, "{cmd}");
            assert_eq!(fails(cmd), vec![], "{cmd}");
        }
        assert_eq!(
            fails("GH --hostname h pr create -t x"),
            vec![(
                Action::Pr(Some(PrAction::Create)),
                Case::UnknownOption("--hostname".into())
            )]
        );
        assert_eq!(pushes("GIT push").len(), 1);
        assert_eq!(
            pushes("Git -C sub push")[0].dir,
            PathBuf::from("/work/repo/sub")
        );
        assert_eq!(
            fails("GIT_DIR=/x GIT push"),
            vec![(Action::Push, Case::UnknownOption("GIT_DIR=".into()))]
        );
        for cmd in [
            "GIT commit -m x && git push",
            "Git checkout other && git push",
            "GH pr checkout 3 && git push",
        ] {
            assert!(same_command(cmd), "{cmd}: {:?}", fails(cmd));
        }
        assert_eq!(pushes("GIT status && git push").len(), 1);
        // Behind env, `GH` is gh: a create stays wrapped, a merge is none.
        assert_eq!(
            fails("env GH pr create"),
            vec![(Action::Pr(None), Case::Wrapped)]
        );
        for cmd in [
            "env Gh pr merge 1 --body new",
            "ENV -u GH_TOKEN GH pr merge 1 --body new",
        ] {
            assert_eq!(cl(cmd).items, vec![], "{cmd}");
        }
        // gh and git read their subcommands exactly: `gh PR create` is an
        // unknown command and `git PUSH` doesn't push.
        assert_eq!(cl("gh PR create --title x").items, vec![]);
        assert!(pushes("git PUSH").is_empty());
    }

    #[test]
    fn a_head_folds_unicode_case_as_the_filesystem_does() {
        // macOS finds `/bin/sh` for `ſh` (long s), `ssh` for `ßh` and sudo
        // for `ſudo`, so each is the wrapper it folds to.
        let wrapped = [(Action::Pr(None), Case::Wrapped)];
        for cmd in [
            "ſh -c 'gh pr create -t x'",
            "/bin/ſh -c 'gh pr create -t x'",
            "zſh -c 'gh pr create -t x'",
            "daſh -c 'gh pr edit 3'",
            "ſudo gh pr create",
            "xargſ gh pr create",
            "ßh host gh pr create",
            "ſsh host gh pr create",
            "doc\u{212A}er run x gh pr create",
            "ENV ſudo gh pr create",
        ] {
            assert_eq!(fails(cmd), wrapped, "{cmd}");
        }
        assert_eq!(fails("ſudo git push"), vec![(Action::Push, Case::Wrapped)]);
        assert_eq!(cl("ſudo ls").items, vec![]);
        assert_eq!(fold("ﬆat"), "stat");
        assert_eq!(fold("\u{212A}"), "k");
    }

    #[test]
    fn a_builtin_head_matches_only_exactly() {
        // `CD` isn't the builtin: it runs a `cd` program in a child, so the
        // directory stays where it was.
        for cmd in ["CD sub && git push", "Pushd /abs && git push"] {
            assert_eq!(pushes(cmd)[0].dir, PathBuf::from(CWD), "{cmd}");
            assert_eq!(fails(cmd), vec![], "{cmd}");
        }
        assert_eq!(pushes("POPD && git push")[0].dir, PathBuf::from(CWD));
        assert_eq!(fails("POPD && git push"), vec![]);
    }

    #[test]
    fn deep_env_nesting_falls_back_without_overflowing() {
        let deep = "env ".repeat(10_000);
        assert_eq!(
            fails(&format!("{deep}gh pr create")),
            vec![(Action::Pr(None), Case::Wrapped)]
        );
        assert_eq!(cl(&format!("{deep}ls")).items, vec![]);
    }

    #[test]
    fn an_env_merge_still_blocks_a_later_push() {
        assert!(same_command(
            "env -u GH_TOKEN gh pr merge 1 --squash && git push"
        ));
    }

    #[test]
    fn the_other_wrappers_keep_the_text_test() {
        // Only `env` is read by the command it runs: behind any other
        // wrapper a quoted mention still reads as a wrapped create.
        let wrapped = [(Action::Pr(None), Case::Wrapped)];
        for cmd in [
            "sudo gh issue create --title \"hook refuses gh pr create\"",
            "nohup gh pr merge 1 --body \"Adds a new path.\"",
            "env -u X sudo gh pr merge 1 --body new",
        ] {
            assert_eq!(fails(cmd), wrapped, "{cmd}");
        }
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

    fn same_command(cmd: &str) -> bool {
        fails(cmd)
            .iter()
            .any(|(a, c)| *a == Action::Push && matches!(c, Case::SameCommand(_)))
    }

    #[test]
    fn a_substitution_that_runs_before_a_push_counts_as_earlier() {
        for cmd in [
            "echo $(git commit -qm \"x\" -m \"Co-Authored-By: Claude <noreply@anthropic.com>\") && git push",
            "x=`git commit -m x`; git push",
            "echo \"$(echo $(git checkout other))\"; git push",
            "echo $(sudo ls) && git push",
            "echo $(gh pr checkout 3) && git push",
            "cat <<EOF && git push\n$(git commit -m x)\nEOF",
        ] {
            assert!(same_command(cmd), "{cmd}: {:?}", fails(cmd));
        }
        // Read-only commands, and substitutions after the push, don't.
        for cmd in [
            "echo $(git rev-parse HEAD) && git push",
            "echo $(date) && git push",
            "git push && echo $(git commit -m x)",
            "cat <<'EOF' && git push\n$(git commit -m x)\nEOF",
        ] {
            assert!(!same_command(cmd), "{cmd}: {:?}", fails(cmd));
            assert_eq!(pushes(cmd).len(), 1, "{cmd}");
        }
    }

    #[test]
    fn a_substitution_naming_the_body_file_counts_as_earlier() {
        let file = Path::new("/work/repo/b.md");
        for cmd in [
            "echo $(printf 'Adds x.' > b.md) && gh pr create -t \"feat: x\" -F b.md",
            "x=`cp y b.md`; gh pr create -t t -F b.md",
            "echo $(echo $(tee sub/../b.md)); gh pr create -t t -F b.md",
        ] {
            let c = cl(cmd);
            let g = ghs(cmd);
            assert!(c.earlier_names_file(g[0].index, file, "b.md"), "{cmd}");
        }
        for cmd in [
            "echo $(date) && gh pr create -t t -F b.md",
            "gh pr create -t t -F b.md && echo $(cat > b.md)",
        ] {
            let c = cl(cmd);
            let g = ghs(cmd);
            assert!(!c.earlier_names_file(g[0].index, file, "b.md"), "{cmd}");
        }
    }

    #[test]
    fn a_backquote_head_is_wrapped() {
        assert_eq!(
            fails("`which git` push"),
            vec![(Action::Push, Case::Wrapped)]
        );
        assert_eq!(
            fails("`which gh` pr new -t x"),
            vec![(Action::Pr(None), Case::Wrapped)]
        );
        assert_eq!(cl("`which ls` -l").items, vec![]);
    }

    #[test]
    fn after_an_unlisted_option_any_later_guarded_word_fails_closed() {
        for (cmd, opt) in [
            ("git --git-dir .git --work-tree . push", "--git-dir"),
            ("git --namespace a b c push origin", "--namespace"),
            ("git --bare log --grep push", "--bare"),
        ] {
            assert_eq!(
                fails(cmd),
                vec![(Action::Push, Case::UnknownOption(opt.into()))],
                "{cmd}"
            );
        }
        for (cmd, opt) in [
            ("gh --hostname h extra pr create -t x", "--hostname"),
            ("gh pr --hostname h extra create -t x", "--hostname"),
            ("gh --a x --b y pr new", "--a"),
        ] {
            assert_eq!(
                fails(cmd),
                vec![(
                    Action::Pr(Some(PrAction::Create)),
                    Case::UnknownOption(opt.into())
                )],
                "{cmd}"
            );
        }
        assert_eq!(cl("gh --hostname h pr view 3").items, vec![]);
        assert_eq!(cl("git --bare log").items, vec![]);
    }

    #[test]
    fn gh_pr_checkout_before_a_push_is_the_same_command() {
        for cmd in [
            "gh pr checkout 3 && git push",
            "gh pr co 3; git push",
            "gh -R o/r pr checkout 3 && git push",
        ] {
            assert!(same_command(cmd), "{cmd}: {:?}", fails(cmd));
        }
        assert_eq!(cl("gh pr checkout 3").items, vec![]);
        assert_eq!(pushes("gh pr view 3 && git push").len(), 1);
    }

    #[test]
    fn gh_pr_new_is_gh_pr_create() {
        for cmd in [
            "gh pr new --title x",
            "gh -R o/r pr new",
            "gh pr --repo o/r new -t x",
        ] {
            let g = ghs(cmd);
            assert_eq!(g.len(), 1, "{cmd}");
            assert_eq!(g[0].action, PrAction::Create, "{cmd}");
        }
        assert_eq!(
            fails("sudo gh pr new --title x"),
            vec![(Action::Pr(None), Case::Wrapped)]
        );
        assert_eq!(fails("$GH pr new"), vec![(Action::Pr(None), Case::Wrapped)]);
        assert!(named_in_text("gh pr new").pr);
        assert!(!named_in_text("gh pr news").pr);
        assert_eq!(cl("gh pr news").items, vec![]);
    }

    #[test]
    fn the_command_coarse_test_joins_a_backslash_newline() {
        assert!(named_in_command("gi\\\nt push").push);
        assert!(!named_in_command("cd x\\\ngit push").push);
        assert!(named_in_command("cd x\ngit push").push);
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
