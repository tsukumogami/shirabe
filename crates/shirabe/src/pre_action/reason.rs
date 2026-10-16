//! The deny reason: one block per broken rule (PRD R5) and one paragraph per
//! case the hook couldn't decide (R7).
//!
//! A broken-rule block reads
//!
//! ```text
//! <rule id>: <summary>: <detail>; <detail>
//!   full text: <file> lines <first>-<last>
//! ```
//!
//! with the blocks in the order the rules appear in the registry. A
//! fail-closed paragraph names the action, the case (by the word R7 gives
//! it), the rules the action is guarded by and the fix, and ends by telling
//! the agent to ask the user. It never names the off switch: that is for the
//! person running the host, and a reason that names it invites the agent to
//! turn the check off.

use std::path::PathBuf;

use super::registry::RuleRange;
use super::{PR_RULES, PUSH_RULES};

/// The `gh pr` action word.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PrAction {
    Create,
    Edit,
}

/// The guarded action a deny is about.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    /// A `gh pr create` or `gh pr edit`; `None` when only the coarse test
    /// saw it, which can't tell which.
    Pr(Option<PrAction>),
    Push,
}

impl Action {
    fn label(self) -> &'static str {
        match self {
            Action::Pr(Some(PrAction::Create)) => "gh pr create",
            Action::Pr(Some(PrAction::Edit)) => "gh pr edit",
            Action::Pr(None) => "gh pr create` or `gh pr edit",
            Action::Push => "git push",
        }
    }

    /// The rules this action is guarded by.
    pub fn rules(self) -> &'static [&'static str] {
        match self {
            Action::Pr(_) => PR_RULES,
            Action::Push => PUSH_RULES,
        }
    }
}

/// A case the hook can't decide, which denies the guarded action (PRD R7).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Case {
    /// Case 2: the input isn't a PreToolUse document with a command.
    HookInput,
    /// Case 3.
    Quote,
    /// Case 3: command substitutions nested past the tokenizer's limit.
    Nesting,
    /// Case 4: a body form the hook can't read, by name (`--fill`, `--web`).
    BodyFlag(String),
    /// Case 4: `-F -`.
    Stdin,
    /// Case 4: a command or variable expansion, `$'...'` or `~` in the body.
    BodyExpansion,
    /// Case 4: short flags combined in one word (`-dt`); the word.
    CombinedFlags(String),
    /// Case 4: an unquoted here-document whose lines hold `$` or a backquote.
    HereDocExpansion,
    /// Case 4: the body file doesn't exist.
    BodyFileMissing(PathBuf),
    /// Case 4: the body file is a symlink, a FIFO, a device, a directory.
    NotRegularFile(PathBuf),
    /// Case 4: larger than 1 MiB.
    TooLarge(PathBuf),
    /// Case 4: it can't be read.
    Unreadable(PathBuf),
    /// Case 4: a `gh pr create` with no body.
    NoBody,
    /// Case 5: a `gh pr create` with no title.
    NoTitle,
    /// A title given as an expansion, which can't be read either.
    TitleExpansion,
    /// Case 6: the registry can't answer for this rule.
    Registry { id: String, what: String },
    /// Case 7, decided by the classifier: the directory a push runs in is
    /// unknown.
    Directory(String),
    /// Case 7: HEAD is detached and the push names no refspec.
    DetachedHead,
    /// Case 7: a push source that doesn't resolve to a commit, starts with
    /// `-`, or is an expansion.
    Source(String),
    /// Case 7: more than 1,000 commits to check.
    TooManyCommits,
    /// Case 7: the push's directory isn't inside a work tree git will read.
    WorkTree(PathBuf),
    /// Case 7: a push option R4 doesn't list.
    PushOption(String),
    /// Case 7: a push with no refspec whose configuration (`push.default`
    /// set to `matching`, or a `remote.<name>.push` refspec) may send more
    /// than the current branch; the setting's name.
    PushConfig(String),
    /// Case 7: a remote that is an expansion, or a configured remote whose
    /// name isn't a plain word.
    Remote(String),
    /// Case 8: a git call of the push check failed or ran out of time, or
    /// the repository is a partial clone and git is too old to keep it
    /// from fetching.
    Git(String),
    /// Case 8.
    Deadline,
    /// Case 8: the evaluation crashed.
    Crash,
    /// Case 9: a global option the hook doesn't understand, or a leading
    /// `GIT_...=` assignment on a push.
    UnknownOption(String),
    /// Case 10.
    Wrapped,
    /// Case 11.
    SameCommand(String),
    /// Case 12.
    Oversize,
}

/// One fail-closed case on one action.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FailClosed {
    pub action: Action,
    pub case: Case,
}

/// One broken rule: its id, the summary and range read from the registry,
/// and the details of where it breaks.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Broken {
    pub id: String,
    pub summary: String,
    pub range: RuleRange,
    pub details: Vec<String>,
}

const READ_FORMS: &str = "The hook reads a body given as `--body <text>`, `-b <text>`, \
    `--body=<text>`, `--body-file <path>`, `-F <path>` or `--body-file=<path>`, or as \
    \"$(cat <<'EOF' ... EOF)\" (an unquoted delimiter only when the lines hold no `$` or \
    backquote).";

/// The case word R7 names, a short explanation, and the fix.
fn describe(case: &Case) -> (String, String, &'static str) {
    let path = |p: &PathBuf| format!("`{}`", p.display());
    match case {
        Case::HookInput => (
            "hook input".into(),
            "the hook input isn't a PreToolUse document with a command".into(),
            "re-run the command; if this keeps happening, the host is sending input the hook doesn't understand.",
        ),
        Case::Quote => (
            "quote".into(),
            "the command has an unterminated quote, command substitution or `${`".into(),
            "close the quote, or put long text in a file and pass it with `--body-file`.",
        ),
        Case::Nesting => (
            "nested".into(),
            format!(
                "the command nests command substitutions more than {} deep",
                super::tokenize::MAX_DEPTH
            ),
            "flatten the command: run the inner commands on their own first, or put long text in a file and pass it with `--body-file`.",
        ),
        Case::BodyFlag(flag) => (
            format!("`{flag}`"),
            "the body comes from somewhere the hook can't see".into(),
            "give the body in a form the hook reads.",
        ),
        Case::Stdin => (
            "stdin".into(),
            "`-F -` reads the body from stdin, which the hook can't see".into(),
            "write the body to a file and pass `--body-file <path>`.",
        ),
        Case::BodyExpansion => (
            "body".into(),
            "the body is a command or variable expansion, `$'...'` or a `~` path, which the hook doesn't evaluate".into(),
            "give the body as literal text or a file path.",
        ),
        Case::HereDocExpansion => (
            "body".into(),
            "the here-document's delimiter is unquoted and its lines hold `$` or a backquote, which the shell would expand".into(),
            "quote the delimiter (`<<'EOF'`) or write the body to a file.",
        ),
        Case::BodyFileMissing(p) => (
            path(p),
            "the body file doesn't exist".into(),
            "create the file first, in a separate command, then run this one.",
        ),
        Case::NotRegularFile(p) => (
            "regular file".into(),
            format!("{} isn't a regular file (a symlink, FIFO, device or directory)", path(p)),
            "pass a regular file.",
        ),
        Case::TooLarge(p) => (
            "1 MiB".into(),
            format!("{} is larger than 1 MiB", path(p)),
            "shorten the body.",
        ),
        Case::Unreadable(p) => (
            path(p),
            "the body file can't be read".into(),
            "make the file readable, or pass the body another way.",
        ),
        Case::NoBody => (
            "no body".into(),
            "the command gives no body".into(),
            "give the body with `--body` or `--body-file`.",
        ),
        Case::NoTitle => (
            "title".into(),
            "the command gives no title".into(),
            "give the title with `--title`.",
        ),
        Case::TitleExpansion => (
            "title".into(),
            "the title is a command or variable expansion, which the hook doesn't evaluate".into(),
            "give the title as literal text.",
        ),
        Case::Registry { id, what } => (
            if id.is_empty() {
                "registry".into()
            } else {
                format!("`{id}`")
            },
            format!("the rule registry can't be read for it: {what}"),
            "reinstall the shirabe plugin and the shirabe binary from the same release.",
        ),
        Case::Directory(why) => (
            "directory".into(),
            why.clone(),
            "run the push from the repository's directory, or with `git -C <path>` and a literal path.",
        ),
        Case::DetachedHead => (
            "HEAD".into(),
            "HEAD is detached and the push names no refspec, so what it pushes is unknown".into(),
            "name what to push, as `git push <remote> HEAD:refs/heads/<branch>`.",
        ),
        Case::Source(src) => (
            format!("`{src}`"),
            "the push source doesn't resolve to a commit in this repository, starts with `-`, or is an expansion the hook doesn't evaluate".into(),
            "name a branch, tag or commit that exists, as a literal word.",
        ),
        Case::TooManyCommits => (
            "1000 commits".into(),
            "the push would send more than 1000 commits, more than the hook checks".into(),
            "push in smaller steps, or ask the user to run this push.",
        ),
        Case::WorkTree(dir) => (
            "work tree".into(),
            format!("{} isn't inside a git work tree that git will read", path(dir)),
            "run the push from inside the repository's work tree.",
        ),
        Case::PushOption(opt) => (
            format!("`{opt}`"),
            "the hook doesn't understand this push option, which could change what the push sends".into(),
            "run the push without it.",
        ),
        Case::PushConfig(key) => (
            format!("`{key}`"),
            format!("the push names no refspec and `{key}` is set, so it may send more than the current branch"),
            "name what to push, for example `git push origin <branch>`.",
        ),
        Case::CombinedFlags(flag) => (
            format!("`{flag}`"),
            "it combines short flags, which the hook doesn't take apart, so it can't tell which word is the title or body".into(),
            "give each flag as a word of its own, for example `-d -t <title>`.",
        ),
        Case::Remote(name) => (
            format!("`{name}`"),
            "the push's remote is an expansion, or a configured remote whose name isn't made of letters, digits, `.`, `_` and `-`".into(),
            "push to a remote with a plain name, given as a literal word.",
        ),
        Case::Git(why) => (
            "git".into(),
            why.clone(),
            "check that `git` works in this repository and try again; a partial clone needs git 2.44 or later.",
        ),
        Case::Deadline => (
            "25 seconds".into(),
            "the check ran past 25 seconds".into(),
            "try again; if it keeps timing out, the repository or the body file is too large to check in time.",
        ),
        Case::Crash => (
            "crash".into(),
            "the check crashed before it could decide".into(),
            "try again; if it keeps crashing, update the shirabe binary.",
        ),
        Case::UnknownOption(opt) => (
            format!("`{opt}`"),
            "the hook doesn't understand this global option, which could change what the command acts on".into(),
            "run the command without it.",
        ),
        Case::Wrapped => (
            "wrapped".into(),
            "the guarded command runs behind a wrapper, a variable or a command substitution, which the hook can't see through".into(),
            "run it as a plain command of its own, not through `sudo`, `env`, `bash -c`, `eval`, a variable or `$(...)`.",
        ),
        Case::SameCommand(what) => (
            "same command".into(),
            what.clone(),
            "run the earlier part as a command of its own first, then run this one by itself.",
        ),
        Case::Oversize => (
            "4 MiB".into(),
            "the hook input is larger than 4 MiB".into(),
            "shorten the command; put long text in a file and pass it with `--body-file`.",
        ),
    }
}

fn is_body_case(case: &Case) -> bool {
    matches!(
        case,
        Case::BodyFlag(_)
            | Case::CombinedFlags(_)
            | Case::Stdin
            | Case::BodyExpansion
            | Case::HereDocExpansion
            | Case::BodyFileMissing(_)
            | Case::NotRegularFile(_)
            | Case::TooLarge(_)
            | Case::Unreadable(_)
            | Case::NoBody
    )
}

/// The paragraph for one fail-closed case.
pub fn fail_closed(f: &FailClosed) -> String {
    let (word, why, fix) = describe(&f.case);
    let mut out = format!(
        "shirabe could not check this `{}` ({word}: {why}), so it is denied.\n\
         It is guarded by: {}.\n\
         Fix: {fix}",
        f.action.label(),
        f.action.rules().join(", "),
    );
    if is_body_case(&f.case) {
        out.push('\n');
        out.push_str(READ_FORMS);
    }
    out.push_str("\nIf you believe this deny is wrong, ask the user.");
    out
}

/// The whole reason: the broken-rule blocks, sorted by the caller into
/// registry order, under a line naming the `actions` that broke them (a
/// command can break PR-body rules and the push rule at once), then each
/// fail-closed paragraph once.
pub fn render(actions: &[Action], broken: &[Broken], fails: &[FailClosed]) -> String {
    let mut parts: Vec<String> = Vec::new();
    if !broken.is_empty() {
        let mut named: Vec<Action> = Vec::new();
        for a in actions {
            if !named.contains(a) {
                named.push(*a);
            }
        }
        if named.is_empty() {
            named.push(Action::Pr(None));
        }
        let labels: Vec<String> = named.iter().map(|a| format!("`{}`", a.label())).collect();
        let mut s = if labels.len() == 1 {
            format!("shirabe denied this {} before it ran.", labels[0])
        } else {
            format!(
                "shirabe denied this command's {} before they ran.",
                labels.join(" and ")
            )
        };
        for b in broken {
            s.push_str(&format!(
                "\n\n{}: {}: {}\n  full text: {} lines {}-{}",
                b.id,
                b.summary,
                b.details.join("; "),
                b.range.path,
                b.range.first,
                b.range.last
            ));
        }
        parts.push(s);
    }
    for f in fails {
        let p = fail_closed(f);
        if !parts.contains(&p) {
            parts.push(p);
        }
    }
    parts.join("\n\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn range() -> RuleRange {
        RuleRange {
            path: "references/pr-body-conformance.md".into(),
            first: 51,
            last: 56,
        }
    }

    #[test]
    fn a_block_per_rule_with_details_joined() {
        let r = render(
            &[Action::Pr(Some(PrAction::Create))],
            &[Broken {
                id: "pr-body/one-separator".into(),
                summary: "Needs one separator".into(),
                range: range(),
                details: vec!["first".into(), "second".into()],
            }],
            &[],
        );
        assert_eq!(
            r,
            "shirabe denied this `gh pr create` before it ran.\n\n\
             pr-body/one-separator: Needs one separator: first; second\n  \
             full text: references/pr-body-conformance.md lines 51-56"
        );
    }

    #[test]
    fn every_case_names_its_word_and_asks_the_user() {
        let p = PathBuf::from("/x/b.md");
        let cases = [
            (Case::HookInput, "hook input"),
            (Case::Quote, "quote"),
            (Case::Nesting, "nested"),
            (Case::BodyFlag("--fill".into()), "--fill"),
            (Case::Stdin, "stdin"),
            (Case::BodyExpansion, "expansion"),
            (Case::BodyFileMissing(p.clone()), "/x/b.md"),
            (Case::NotRegularFile(p.clone()), "regular file"),
            (Case::TooLarge(p.clone()), "1 MiB"),
            (Case::NoBody, "no body"),
            (Case::NoTitle, "title"),
            (
                Case::Registry {
                    id: "pr-body/one-separator".into(),
                    what: "x".into(),
                },
                "pr-body/one-separator",
            ),
            (Case::Directory("cd \"$DIR\"".into()), "directory"),
            (Case::DetachedHead, "HEAD"),
            (Case::Source("nosuch".into()), "`nosuch`"),
            (Case::TooManyCommits, "1000 commits"),
            (Case::WorkTree(p.clone()), "work tree"),
            (Case::PushOption("--new".into()), "`--new`"),
            (Case::PushConfig("push.default".into()), "`push.default`"),
            (Case::CombinedFlags("-dt".into()), "`-dt`"),
            (Case::Remote("fo+o".into()), "`fo+o`"),
            (Case::Git("x".into()), "git"),
            (Case::Deadline, "25 seconds"),
            (Case::UnknownOption("--git-dir=x".into()), "--git-dir=x"),
            (Case::Wrapped, "wrapped"),
            (Case::SameCommand("x".into()), "same command"),
            (Case::Oversize, "4 MiB"),
        ];
        for (case, word) in cases {
            let body = is_body_case(&case);
            let s = fail_closed(&FailClosed {
                action: Action::Push,
                case,
            });
            assert!(s.contains(word), "{word}: {s}");
            assert!(s.contains("ask the user"), "{s}");
            assert!(!s.contains("SHIRABE_PRE_ACTION_HOOK"), "{s}");
            assert!(s.contains("commit/no-ai-trailer"), "{s}");
            assert_eq!(s.contains("--body-file=<path>"), body, "{s}");
        }
    }

    #[test]
    fn a_command_breaking_pr_and_push_rules_names_both_actions() {
        let block = |id: &str| Broken {
            id: id.into(),
            summary: "s".into(),
            range: range(),
            details: vec!["d".into()],
        };
        let r = render(
            &[
                Action::Push,
                Action::Pr(Some(PrAction::Create)),
                Action::Push,
            ],
            &[
                block("commit/no-ai-trailer"),
                block("pr-body/one-separator"),
            ],
            &[],
        );
        assert!(
            r.starts_with(
                "shirabe denied this command's `git push` and `gh pr create` before they ran.\n\n\
                 commit/no-ai-trailer: s: d\n"
            ),
            "{r}"
        );
        assert_eq!(r.matches("shirabe denied").count(), 1, "{r}");
    }

    #[test]
    fn a_repeated_case_is_rendered_once() {
        let f = FailClosed {
            action: Action::Push,
            case: Case::Wrapped,
        };
        let r = render(&[], &[], &[f.clone(), f]);
        assert_eq!(r.matches("wrapped").count(), 1, "{r}");
    }
}
