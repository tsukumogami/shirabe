//! The title and body a `gh pr create` or `gh pr edit` submits (PRD R3, R6,
//! R7 cases 4 and 5).
//!
//! The title comes from `--title`/`-t`; the body from `--body`/`-b`/`--body=`
//! or `--body-file`/`-F`/`--body-file=`, a relative path resolved against the
//! segment's directory. A body of the form `"$(cat <<'EOF' ... EOF)"`, or
//! with the delimiter double-quoted, is the here-document's lines as written;
//! with an unquoted delimiter only when those lines hold no `$` and no
//! backquote. Every other form is one the hook can't read and is refused by
//! name, so the deny can say what to do instead.
//!
//! A body file is untrusted and may be anything: it is read only after
//! `lstat` shows a regular file, through an `O_NONBLOCK | O_NOFOLLOW` open
//! (so a FIFO or a symlink swapped in after the `lstat` can't block or
//! redirect it), checked again with `fstat` on the open descriptor, and read
//! up to 1 MiB. Its lines reach the validator and never the reason.

use std::io::Read;
use std::path::{Path, PathBuf};

use super::classify::{normalize, Classified, GhSegment};
use super::reason::{Case, PrAction};
use super::tokenize::{Tokenized, Word};

/// The most a body file may hold.
pub const MAX_BODY_FILE: u64 = 1024 * 1024;

/// What the command submits. A `None` was not given (only an edit may leave
/// one out).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Submitted {
    pub title: Option<String>,
    pub body: Option<String>,
}

/// Flags whose body the hook can't see, with the name the deny gives each.
/// The short forms are gh's own aliases (`-f` is `--fill`), so they are
/// refused under the long name.
const UNREADABLE_FLAGS: &[(&str, &str)] = &[
    ("--fill", "--fill"),
    ("-f", "--fill"),
    ("--fill-first", "--fill-first"),
    ("--fill-verbose", "--fill-verbose"),
    ("--web", "--web"),
    ("-w", "--web"),
    ("--editor", "--editor"),
    ("-e", "--editor"),
    ("--template", "--template"),
    ("-T", "--template"),
];

/// Read what `seg` submits. `tok` is the command the segment came from, for
/// a here-document body, and `classified` its classification, for the check
/// that no earlier segment writes the body file.
pub fn read(seg: &GhSegment, tok: &Tokenized, classified: &Classified) -> Result<Submitted, Case> {
    let mut title: Option<Word> = None;
    let mut body: Option<Word> = None;
    let mut file: Option<Word> = None;
    let mut i = 0;
    let ws = &seg.words;
    while i < ws.len() {
        let w = &ws[i];
        // `--flag=value` for a long option; otherwise the value is the next
        // word.
        let (flag, inline) = match w.text.split_once('=') {
            Some((f, v)) if f.starts_with("--") => (
                f,
                Some(Word {
                    text: v.to_string(),
                    tilde: v.starts_with('~') && w.bare,
                    ..w.clone()
                }),
            ),
            _ => (w.text.as_str(), None),
        };
        if let Some((_, name)) = UNREADABLE_FLAGS.iter().find(|(f, _)| *f == flag) {
            return Err(Case::BodyFlag(name.to_string()));
        }
        let slot = match flag {
            "--title" | "-t" => Some(&mut title),
            "--body" | "-b" => Some(&mut body),
            "--body-file" | "-F" => Some(&mut file),
            _ => None,
        };
        if let Some(slot) = slot {
            match inline {
                Some(v) => *slot = Some(v),
                None => {
                    if let Some(v) = ws.get(i + 1) {
                        *slot = Some(v.clone());
                        i += 1;
                    }
                }
            }
        }
        i += 1;
    }

    // A title the shell would expand is as unreadable as such a body; PB1
    // would otherwise judge the literal `$T`.
    let title = match title {
        Some(w) if w.expansion || w.ansi_c => return Err(Case::TitleExpansion),
        Some(w) => Some(w.text),
        None => None,
    };
    let body = match (body, file) {
        (Some(w), _) => Some(inline_body(&w, tok)?),
        (None, Some(w)) => Some(file_body(&w, seg, classified)?),
        (None, None) => None,
    };
    if seg.action == PrAction::Create {
        if title.is_none() {
            return Err(Case::NoTitle);
        }
        if body.is_none() {
            return Err(Case::NoBody);
        }
    }
    Ok(Submitted { title, body })
}

/// A `--body` value: literal text, or the here-document form.
fn inline_body(w: &Word, tok: &Tokenized) -> Result<String, Case> {
    if let Some(sub) = w.dq_substitution.and_then(|i| tok.substitutions.get(i)) {
        return heredoc_body(&sub.inner);
    }
    if w.expansion || w.ansi_c {
        return Err(Case::BodyExpansion);
    }
    Ok(w.text.clone())
}

/// The lines of `cat <<DELIM ... DELIM` when that is all the substitution
/// holds. The substitution drops trailing newlines, as the shell does.
fn heredoc_body(inner: &Tokenized) -> Result<String, Case> {
    let only_cat = match inner.segments.as_slice() {
        [seg] => matches!(
            seg.words.as_slice(),
            [cat, op] if cat.text == "cat" && cat.bare && op.heredoc == Some(0)
        ),
        _ => false,
    };
    if !only_cat || inner.heredocs.len() != 1 || !inner.substitutions.is_empty() {
        return Err(Case::BodyExpansion);
    }
    let h = &inner.heredocs[0];
    if !h.terminated {
        return Err(Case::BodyExpansion);
    }
    if !h.quoted && (h.body.contains('$') || h.body.contains('`')) {
        return Err(Case::HereDocExpansion);
    }
    Ok(h.body.trim_end_matches('\n').to_string())
}

/// A `--body-file` value: refused forms, the same-command check, then the
/// bounded read.
fn file_body(w: &Word, seg: &GhSegment, classified: &Classified) -> Result<String, Case> {
    if w.text == "-" {
        return Err(Case::Stdin);
    }
    // A `~` path is the shell's expansion too; the hook doesn't guess at it
    // from its own `HOME`, which need not be the one the command runs with.
    if w.expansion || w.ansi_c || w.tilde || w.text.is_empty() {
        return Err(Case::BodyExpansion);
    }
    let given = Path::new(&w.text);
    let path: PathBuf = if given.is_absolute() {
        given.to_path_buf()
    } else {
        match &seg.dir {
            Some(d) => d.join(given),
            None => {
                return Err(Case::Directory(format!(
                    "the body file `{}` is a relative path and the directory the command runs in is unknown",
                    w.text
                )))
            }
        }
    };
    if classified.earlier_names_file(seg.index, &normalize(&path), &w.text) {
        return Err(Case::SameCommand(format!(
            "an earlier part of the same command names the body file `{}`, which it may write after the hook reads it",
            w.text
        )));
    }
    read_bounded(&path)
}

/// Read a body file without following a symlink, blocking on a FIFO, or
/// reading more than [`MAX_BODY_FILE`].
pub fn read_bounded(path: &Path) -> Result<String, Case> {
    use rustix::fs::{Mode, OFlags};
    let p = path.to_path_buf();
    let meta = match std::fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Err(Case::BodyFileMissing(p)),
        Err(_) => return Err(Case::Unreadable(p)),
    };
    if !meta.file_type().is_file() {
        return Err(Case::NotRegularFile(p));
    }
    let fd = rustix::fs::open(
        path,
        OFlags::RDONLY | OFlags::NONBLOCK | OFlags::NOFOLLOW | OFlags::CLOEXEC,
        Mode::empty(),
    )
    .map_err(|e| {
        if e == rustix::io::Errno::LOOP {
            Case::NotRegularFile(p.clone())
        } else {
            Case::Unreadable(p.clone())
        }
    })?;
    let file = std::fs::File::from(fd);
    let meta = file.metadata().map_err(|_| Case::Unreadable(p.clone()))?;
    if !meta.file_type().is_file() {
        return Err(Case::NotRegularFile(p));
    }
    if meta.len() > MAX_BODY_FILE {
        return Err(Case::TooLarge(p));
    }
    let mut bytes = Vec::new();
    file.take(MAX_BODY_FILE + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| Case::Unreadable(p.clone()))?;
    if bytes.len() as u64 > MAX_BODY_FILE {
        return Err(Case::TooLarge(p));
    }
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

#[cfg(test)]
mod tests {
    use super::super::classify::{classify, Item};
    use super::super::tokenize::tokenize;
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("shirabe-body-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn submit(cmd: &str, cwd: &Path) -> Result<Submitted, Case> {
        let tok = tokenize(cmd).expect("tokenizes");
        let c = classify(&tok, Some(cwd));
        let seg = c
            .items
            .iter()
            .find_map(|i| match i {
                Item::Gh(g) => Some(g.clone()),
                _ => None,
            })
            .expect("a gh segment");
        read(&seg, &tok, &c)
    }

    fn here(cmd: &str) -> Result<Submitted, Case> {
        submit(cmd, Path::new("/nonexistent-cwd"))
    }

    #[test]
    fn inline_forms() {
        let s = here("gh pr create --title 'feat: x' --body 'a\n\n---\n\nb'").unwrap();
        assert_eq!(s.title.as_deref(), Some("feat: x"));
        assert_eq!(s.body.as_deref(), Some("a\n\n---\n\nb"));
        let s = here("gh pr create -t 'feat: x' -b body").unwrap();
        assert_eq!(s.body.as_deref(), Some("body"));
        let s = here("gh pr create --title='feat: x' --body='a b'").unwrap();
        assert_eq!(s.title.as_deref(), Some("feat: x"));
        assert_eq!(s.body.as_deref(), Some("a b"));
    }

    #[test]
    fn here_document_forms() {
        for q in ["'EOF'", "\"EOF\"", "EOF"] {
            let cmd = format!(
                "gh pr create --title 'feat: x' --body \"$(cat <<{q}\nIt's x.\n\n---\n\nctx\nEOF\n)\""
            );
            let s = here(&cmd).unwrap_or_else(|e| panic!("{q}: {e:?}"));
            assert_eq!(s.body.as_deref(), Some("It's x.\n\n---\n\nctx"), "{q}");
        }
        for line in ["$HOME", "`date`"] {
            let cmd =
                format!("gh pr create --title 'feat: x' --body \"$(cat <<EOF\n{line}\nEOF\n)\"");
            assert_eq!(here(&cmd), Err(Case::HereDocExpansion), "{line}");
            let quoted = cmd.replace("<<EOF", "<<'EOF'");
            assert!(here(&quoted).is_ok(), "{line} quoted");
        }
    }

    #[test]
    fn unreadable_forms_are_refused_by_name() {
        let cases = [
            ("gh pr create --fill", Case::BodyFlag("--fill".into())),
            ("gh pr create -f", Case::BodyFlag("--fill".into())),
            (
                "gh pr create --fill-first",
                Case::BodyFlag("--fill-first".into()),
            ),
            (
                "gh pr create --fill-verbose",
                Case::BodyFlag("--fill-verbose".into()),
            ),
            (
                "gh pr create --title 'feat: x' --web",
                Case::BodyFlag("--web".into()),
            ),
            (
                "gh pr create --title t --editor",
                Case::BodyFlag("--editor".into()),
            ),
            (
                "gh pr create --title t --template x.md",
                Case::BodyFlag("--template".into()),
            ),
            ("gh pr create --title t -F -", Case::Stdin),
            (
                "gh pr create --title t --body \"$BODY\"",
                Case::BodyExpansion,
            ),
            (
                "gh pr create --title t --body \"$(cat b.md)\"",
                Case::BodyExpansion,
            ),
            (
                "gh pr create --title t --body `cat b.md`",
                Case::BodyExpansion,
            ),
            (
                "gh pr create --title t --body $'a\\nb'",
                Case::BodyExpansion,
            ),
            ("gh pr create --title t -F \"$F\"", Case::BodyExpansion),
            ("gh pr create --title t -F ~/b.md", Case::BodyExpansion),
            (
                "gh pr create --title t --body-file=~/b.md",
                Case::BodyExpansion,
            ),
            ("gh pr create --title t", Case::NoBody),
            ("gh pr create --body b", Case::NoTitle),
            ("gh pr create --title \"$T\" --body b", Case::TitleExpansion),
        ];
        for (cmd, want) in cases {
            assert_eq!(here(cmd), Err(want), "{cmd}");
        }
    }

    #[test]
    fn an_edit_may_leave_either_out() {
        assert_eq!(
            here("gh pr edit 12 --add-label x").unwrap(),
            Submitted::default()
        );
        let s = here("gh pr edit 12 --title 'bad title'").unwrap();
        assert_eq!((s.title.as_deref(), s.body), (Some("bad title"), None));
        let s = here("gh pr edit 12 --body b").unwrap();
        assert_eq!((s.title, s.body.as_deref()), (None, Some("b")));
    }

    #[test]
    fn body_files_resolve_against_the_segment_directory() {
        let d = scratch("rel");
        std::fs::create_dir_all(d.join("sub")).unwrap();
        std::fs::write(d.join("sub/b.md"), "x\n\n---\n\ny\n").unwrap();
        for cmd in [
            "gh pr create --title t -F sub/b.md",
            "cd sub && gh pr create --title t --body-file=b.md",
            "cd sub && gh pr create --title t --body-file b.md",
            "gh pr create --title t -F ./sub/../sub/b.md",
        ] {
            let s = submit(cmd, &d).unwrap_or_else(|e| panic!("{cmd}: {e:?}"));
            assert_eq!(s.body.as_deref(), Some("x\n\n---\n\ny\n"), "{cmd}");
        }
        let abs = format!("gh pr create --title t -F {}", d.join("sub/b.md").display());
        assert!(here(&abs).is_ok());
        let tok = tokenize("gh pr create --title t -F b.md").unwrap();
        let c = classify(&tok, None);
        let Item::Gh(g) = &c.items[0] else { panic!() };
        assert!(matches!(read(g, &tok, &c), Err(Case::Directory(_))));
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn an_earlier_segment_naming_the_body_file_is_same_command() {
        let d = scratch("same");
        std::fs::write(d.join("b.md"), "x\n\n---\n\ny\n").unwrap();
        let r = submit(
            "printf 'x' > b.md && gh pr create --title 'feat: x' -F b.md",
            &d,
        );
        assert!(matches!(r, Err(Case::SameCommand(_))), "{r:?}");
        let r = submit("ls && gh pr create --title 'feat: x' -F b.md", &d);
        assert!(r.is_ok(), "{r:?}");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn bounded_reads_refuse_what_isnt_a_small_regular_file() {
        let d = scratch("bounded");
        let missing = d.join("nope.md");
        assert_eq!(
            read_bounded(&missing),
            Err(Case::BodyFileMissing(missing.clone()))
        );
        assert_eq!(read_bounded(&d), Err(Case::NotRegularFile(d.clone())));
        let big = d.join("big.md");
        std::fs::write(&big, vec![b'a'; MAX_BODY_FILE as usize + 1]).unwrap();
        assert_eq!(read_bounded(&big), Err(Case::TooLarge(big.clone())));
        let edge = d.join("edge.md");
        std::fs::write(&edge, vec![b'a'; MAX_BODY_FILE as usize]).unwrap();
        assert!(read_bounded(&edge).is_ok(), "exactly 1 MiB is read");
        let real = d.join("real.md");
        std::fs::write(&real, "x").unwrap();
        let link = d.join("link.md");
        std::os::unix::fs::symlink(&real, &link).unwrap();
        assert_eq!(read_bounded(&link), Err(Case::NotRegularFile(link.clone())));
        let fifo = d.join("fifo");
        let made = std::process::Command::new("mkfifo")
            .arg(&fifo)
            .status()
            .unwrap();
        assert!(made.success());
        assert_eq!(read_bounded(&fifo), Err(Case::NotRegularFile(fifo.clone())));
        let _ = std::fs::remove_dir_all(&d);
    }
}
