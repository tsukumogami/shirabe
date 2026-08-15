//! Reader and classifier for `/execute`'s closed write-target set.
//!
//! The set used to be a paragraph of English in `skills/execute/SKILL.md`
//! (Security Considerations, point 2). Two components need to read it — the
//! adherence hook and the determination — so it now ships as a data file,
//! `skills/execute/write-targets.json`, and the prose points at that file
//! rather than restating it. This module is the only parser of that format.
//!
//! What the declaration says:
//!
//! - `path_classes` name globs, relative to the repository root, that `/execute`
//!   may write. A `{topic}` placeholder stands for the topic slug and matches
//!   the regex under `placeholders`, so `wip/execute_{topic}_**` covers the state
//!   file and the scratch beside it without the reader knowing the slug.
//! - `command_classes` name argv prefixes for the remote writes, which are not
//!   filesystem paths at all: the home pull request is edited through `gh`.
//! - `schema` is checked on load. A declaration carrying a schema this build
//!   does not understand is rejected rather than half-read, so a future format
//!   change cannot be silently misclassified by an old binary.
//!
//! Matching is lexical. A path is normalized (leading `./` dropped, duplicate
//! slashes collapsed, `.`/`..` segments folded) before it is compared, and a
//! path that folds above the root is Outside — a path that cannot be shown to
//! land inside the set is not inside it.
//!
//! Nothing here decides anything. It answers whether a target is inside the
//! declared set; the caller decides what to do about the answer.

// The classifier is wired into the hook subcommand by a later issue in this
// plan. Until then nothing in the binary calls it, and only the unit tests
// below exercise it.
#![allow(dead_code)]

use std::fmt;
use std::path::{Path, PathBuf};

use regex::Regex;

/// Where the declaration sits under the plugin root.
pub const DECLARATION_RELATIVE_PATH: &str = "skills/execute/write-targets.json";

/// The only `schema` value this build understands.
pub const SUPPORTED_SCHEMA: &str = "write-targets/v1";

/// Read cap on the declaration. It is a plugin-shipped file of a few kilobytes;
/// the cap keeps a hook process from reading an arbitrarily large file that
/// ended up at that path, matching the binary's other input guards.
const MAX_DECLARATION_BYTES: u64 = 64 * 1024;

/// Why a declaration could not be turned into a [`WriteTargets`].
///
/// Every variant is a hard error. Callers on a hook path are expected to treat
/// a load failure as "allow and record", but that policy belongs to the caller:
/// this module reports what went wrong and stops there.
#[derive(Debug)]
pub enum LoadError {
    /// `CLAUDE_PLUGIN_ROOT` is unset or empty, so the declaration cannot be
    /// located.
    PluginRootUnset,
    /// The file could not be opened, stat-ed, or read.
    Io { path: PathBuf, message: String },
    /// The file is larger than [`MAX_DECLARATION_BYTES`].
    TooLarge { path: PathBuf, bytes: u64 },
    /// The bytes are not JSON, or are JSON in the wrong shape.
    Malformed(String),
    /// The `schema` field names a format this build does not understand.
    UnsupportedSchema(String),
}

impl fmt::Display for LoadError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LoadError::PluginRootUnset => write!(f, "CLAUDE_PLUGIN_ROOT is not set"),
            LoadError::Io { path, message } => {
                write!(f, "cannot read {}: {message}", path.display())
            }
            LoadError::TooLarge { path, bytes } => write!(
                f,
                "{} is {bytes} bytes, over the {MAX_DECLARATION_BYTES}-byte cap",
                path.display()
            ),
            LoadError::Malformed(what) => write!(f, "malformed write-target declaration: {what}"),
            LoadError::UnsupportedSchema(found) => write!(
                f,
                "write-target declaration has schema {found:?}, expected {SUPPORTED_SCHEMA:?}"
            ),
        }
    }
}

/// The verdict on one target.
///
/// Borrows the class and pattern out of the declaration, so a caller can name
/// the matched class in a message without the classifier allocating.
#[derive(Debug, PartialEq, Eq)]
pub enum Classification<'a> {
    /// The target falls in the declared set, under this class, by this pattern.
    /// For a command class the pattern is the matched argv prefix, joined by
    /// spaces.
    Inside { class: &'a str, pattern: &'a str },
    /// The target is outside the declared set.
    Outside,
}

impl Classification<'_> {
    pub fn is_inside(&self) -> bool {
        matches!(self, Classification::Inside { .. })
    }
}

/// A parsed, compiled declaration.
pub struct WriteTargets {
    skill: String,
    path_classes: Vec<PathClass>,
    command_classes: Vec<CommandClass>,
}

struct PathClass {
    id: String,
    patterns: Vec<CompiledPattern>,
}

struct CompiledPattern {
    /// The glob as written in the declaration, carried for reporting.
    source: String,
    regex: Regex,
    /// One entry per `{placeholder}` occurrence: the capture-group name the
    /// glob compiler assigned it, and the placeholder it came from. Occurrences
    /// get distinct group names so a pattern may mention one placeholder twice.
    placeholders: Vec<(String, String)>,
}

struct CommandClass {
    id: String,
    /// Each prefix as tokens, plus the same prefix joined for reporting.
    prefixes: Vec<(Vec<String>, String)>,
}

/// The declaration's path under `plugin_root`.
pub fn declaration_path(plugin_root: &Path) -> PathBuf {
    plugin_root.join(DECLARATION_RELATIVE_PATH)
}

/// The plugin root as the harness exports it to a hook process.
pub fn plugin_root_from_env() -> Result<PathBuf, LoadError> {
    match std::env::var("CLAUDE_PLUGIN_ROOT") {
        Ok(v) if !v.is_empty() => Ok(PathBuf::from(v)),
        _ => Err(LoadError::PluginRootUnset),
    }
}

/// Load the declaration the way a hook process does: resolve
/// `${CLAUDE_PLUGIN_ROOT}`, then read the file beneath it.
pub fn load_from_plugin_root() -> Result<WriteTargets, LoadError> {
    let root = plugin_root_from_env()?;
    load(&declaration_path(&root))
}

/// Load a declaration from an explicit path.
pub fn load(path: &Path) -> Result<WriteTargets, LoadError> {
    let meta = std::fs::metadata(path).map_err(|e| LoadError::Io {
        path: path.to_path_buf(),
        message: e.to_string(),
    })?;
    if meta.len() > MAX_DECLARATION_BYTES {
        return Err(LoadError::TooLarge {
            path: path.to_path_buf(),
            bytes: meta.len(),
        });
    }
    let raw = std::fs::read_to_string(path).map_err(|e| LoadError::Io {
        path: path.to_path_buf(),
        message: e.to_string(),
    })?;
    parse(&raw)
}

/// Parse and compile declaration bytes.
pub fn parse(json: &str) -> Result<WriteTargets, LoadError> {
    let v: serde_json::Value =
        serde_json::from_str(json).map_err(|e| LoadError::Malformed(e.to_string()))?;

    let schema = v
        .get("schema")
        .and_then(|s| s.as_str())
        .ok_or_else(|| LoadError::Malformed("missing string field \"schema\"".into()))?;
    if schema != SUPPORTED_SCHEMA {
        return Err(LoadError::UnsupportedSchema(schema.to_string()));
    }

    let skill = v
        .get("skill")
        .and_then(|s| s.as_str())
        .ok_or_else(|| LoadError::Malformed("missing string field \"skill\"".into()))?
        .to_string();

    let placeholders = parse_placeholders(&v)?;

    let mut path_classes = Vec::new();
    for entry in array_field(&v, "path_classes")? {
        let id = string_field(entry, "id", "path_classes")?;
        let mut patterns = Vec::new();
        for p in array_field(entry, "patterns")? {
            let glob = p.as_str().ok_or_else(|| {
                LoadError::Malformed(format!("path class {id:?} has a non-string pattern"))
            })?;
            patterns.push(compile_glob(glob, &placeholders)?);
        }
        if patterns.is_empty() {
            return Err(LoadError::Malformed(format!(
                "path class {id:?} declares no patterns"
            )));
        }
        path_classes.push(PathClass { id, patterns });
    }
    if path_classes.is_empty() {
        return Err(LoadError::Malformed("\"path_classes\" is empty".into()));
    }

    let mut command_classes = Vec::new();
    // A declaration may legitimately have no remote writes, so this field is
    // optional where path_classes is not.
    if v.get("command_classes").is_some() {
        for entry in array_field(&v, "command_classes")? {
            let id = string_field(entry, "id", "command_classes")?;
            let mut prefixes = Vec::new();
            for p in array_field(entry, "argv_prefixes")? {
                let tokens: Vec<String> = p
                    .as_array()
                    .ok_or_else(|| {
                        LoadError::Malformed(format!(
                            "command class {id:?} has a non-array argv prefix"
                        ))
                    })?
                    .iter()
                    .map(|t| {
                        t.as_str().map(str::to_string).ok_or_else(|| {
                            LoadError::Malformed(format!(
                                "command class {id:?} has a non-string argv token"
                            ))
                        })
                    })
                    .collect::<Result<_, _>>()?;
                if tokens.is_empty() {
                    return Err(LoadError::Malformed(format!(
                        "command class {id:?} has an empty argv prefix, which would match everything"
                    )));
                }
                let display = tokens.join(" ");
                prefixes.push((tokens, display));
            }
            if prefixes.is_empty() {
                return Err(LoadError::Malformed(format!(
                    "command class {id:?} declares no argv prefixes"
                )));
            }
            command_classes.push(CommandClass { id, prefixes });
        }
    }

    Ok(WriteTargets {
        skill,
        path_classes,
        command_classes,
    })
}

impl WriteTargets {
    /// The skill whose write-target set this is.
    pub fn skill(&self) -> &str {
        &self.skill
    }

    /// Classify a repository-relative path, leaving placeholders unbound: any
    /// topic slug matching the declared placeholder pattern satisfies the
    /// match. Use this when the topic is unknown.
    pub fn classify_path(&self, path: &str) -> Classification<'_> {
        self.classify_path_inner(path, None)
    }

    /// Classify a repository-relative path with `{topic}` bound to one slug, so
    /// a path keyed on some *other* topic falls outside the set. The tighter
    /// answer, for callers that know which plan is running.
    ///
    /// A topic that does not itself match the declared placeholder pattern
    /// makes every placeholder-bearing pattern unsatisfiable, which is the
    /// honest answer: nothing can be keyed on a slug the declaration rejects.
    pub fn classify_path_for_topic(&self, path: &str, topic: &str) -> Classification<'_> {
        self.classify_path_inner(path, Some(topic))
    }

    fn classify_path_inner(&self, path: &str, topic: Option<&str>) -> Classification<'_> {
        let Some(normalized) = normalize_path(path) else {
            return Classification::Outside;
        };
        for class in &self.path_classes {
            for pattern in &class.patterns {
                let Some(caps) = pattern.regex.captures(&normalized) else {
                    continue;
                };
                let bound = topic.is_none()
                    || pattern.placeholders.iter().all(|(group, name)| {
                        // Only "topic" is bindable today; other placeholders
                        // stay pattern-matched.
                        name != "topic" || caps.name(group).map(|m| m.as_str()) == topic
                    });
                if bound {
                    return Classification::Inside {
                        class: &class.id,
                        pattern: &pattern.source,
                    };
                }
            }
        }
        Classification::Outside
    }

    /// Classify a command by its argv tokens. A command is inside the set when
    /// its leading tokens equal a declared prefix; the remaining arguments are
    /// not inspected.
    pub fn classify_command(&self, argv: &[&str]) -> Classification<'_> {
        for class in &self.command_classes {
            for (tokens, display) in &class.prefixes {
                if argv.len() >= tokens.len()
                    && tokens.iter().zip(argv).all(|(want, got)| want == got)
                {
                    return Classification::Inside {
                        class: &class.id,
                        pattern: display,
                    };
                }
            }
        }
        Classification::Outside
    }
}

fn array_field<'v>(
    v: &'v serde_json::Value,
    key: &str,
) -> Result<&'v Vec<serde_json::Value>, LoadError> {
    v.get(key)
        .and_then(|f| f.as_array())
        .ok_or_else(|| LoadError::Malformed(format!("missing array field {key:?}")))
}

fn string_field(v: &serde_json::Value, key: &str, ctx: &str) -> Result<String, LoadError> {
    v.get(key)
        .and_then(|f| f.as_str())
        .map(str::to_string)
        .ok_or_else(|| LoadError::Malformed(format!("an entry in {ctx:?} has no string {key:?}")))
}

/// Compile the `placeholders` map into anchored, slash-free regex fragments.
///
/// A placeholder stands for one path component, so its pattern is rejected if
/// it can match a `/`. That keeps `wip/execute_{topic}_**` from being satisfied
/// by a slug that walks into another directory.
fn parse_placeholders(v: &serde_json::Value) -> Result<Vec<(String, String)>, LoadError> {
    let Some(map) = v.get("placeholders") else {
        return Ok(Vec::new());
    };
    let map = map
        .as_object()
        .ok_or_else(|| LoadError::Malformed("\"placeholders\" is not an object".into()))?;
    let mut out = Vec::new();
    for (name, pattern) in map {
        let pattern = pattern.as_str().ok_or_else(|| {
            LoadError::Malformed(format!("placeholder {name:?} has a non-string pattern"))
        })?;
        if pattern.contains('/') {
            return Err(LoadError::Malformed(format!(
                "placeholder {name:?} may not match a path separator"
            )));
        }
        // Compile once here so a bad pattern is a load error rather than a
        // surprise when the first glob using it is compiled.
        Regex::new(pattern).map_err(|e| {
            LoadError::Malformed(format!("placeholder {name:?} is not a valid regex: {e}"))
        })?;
        out.push((name.clone(), pattern.to_string()));
    }
    Ok(out)
}

/// Translate one glob into an anchored regex.
///
/// The glob vocabulary: `*` matches within a path component, `**` crosses
/// components, `?` matches one non-separator character, and `{name}` expands to
/// the named placeholder's pattern under a unique capture group. Everything
/// else is literal.
fn compile_glob(
    glob: &str,
    placeholders: &[(String, String)],
) -> Result<CompiledPattern, LoadError> {
    let mut re = String::from("^");
    let mut used = Vec::new();
    let chars: Vec<char> = glob.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        match chars[i] {
            '*' => {
                if i + 1 < chars.len() && chars[i + 1] == '*' {
                    re.push_str(".*");
                    i += 2;
                } else {
                    re.push_str("[^/]*");
                    i += 1;
                }
            }
            '?' => {
                re.push_str("[^/]");
                i += 1;
            }
            '{' => {
                let close = chars[i..].iter().position(|c| *c == '}').ok_or_else(|| {
                    LoadError::Malformed(format!("pattern {glob:?} has an unclosed placeholder"))
                })?;
                let name: String = chars[i + 1..i + close].iter().collect();
                let pattern = placeholders
                    .iter()
                    .find(|(n, _)| *n == name)
                    .map(|(_, p)| p.clone())
                    .ok_or_else(|| {
                        LoadError::Malformed(format!(
                            "pattern {glob:?} uses undeclared placeholder {name:?}"
                        ))
                    })?;
                let group = format!("ph{}", used.len());
                re.push_str(&format!("(?P<{group}>{pattern})"));
                used.push((group, name));
                i += close + 1;
            }
            c => {
                re.push_str(&regex::escape(&c.to_string()));
                i += 1;
            }
        }
    }
    re.push('$');
    let regex = Regex::new(&re)
        .map_err(|e| LoadError::Malformed(format!("pattern {glob:?} does not compile: {e}")))?;
    Ok(CompiledPattern {
        source: glob.to_string(),
        regex,
        placeholders: used,
    })
}

/// Fold a path into the plain relative form the patterns are written against.
///
/// Returns `None` when the path is absolute or folds above the root: neither
/// can be shown to land inside a set expressed in repository-relative terms.
fn normalize_path(path: &str) -> Option<String> {
    if path.starts_with('/') {
        return None;
    }
    let mut out: Vec<&str> = Vec::new();
    for segment in path.split('/') {
        match segment {
            "" | "." => {}
            ".." => {
                out.pop()?;
            }
            s => out.push(s),
        }
    }
    if out.is_empty() {
        return None;
    }
    Some(out.join("/"))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The declaration as it ships, read from the source tree. The plugin root
    /// at runtime is the repository root; under test it is two levels above the
    /// crate manifest.
    fn shipped() -> WriteTargets {
        load(&declaration_path(&repo_root())).expect("shipped declaration loads")
    }

    fn repo_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .and_then(Path::parent)
            .expect("crate sits two levels under the repo root")
            .to_path_buf()
    }

    #[test]
    fn shipped_declaration_loads_and_names_execute() {
        assert_eq!(shipped().skill(), "execute");
    }

    #[test]
    fn a_path_inside_the_set_and_a_path_outside_it_are_classified() {
        let wt = shipped();
        assert!(wt
            .classify_path("wip/execute_skill-adherence-enforcement_state.md")
            .is_inside());
        assert_eq!(wt.classify_path("src/main.rs"), Classification::Outside);
    }

    #[test]
    fn every_class_the_prose_named_has_a_member() {
        let wt = shipped();
        for (path, class) in [
            ("wip/execute_my-topic_state.md", "state-and-scratch"),
            ("wip/execute_my-topic_scratch/notes.md", "state-and-scratch"),
            ("skills/execute/SKILL.md", "own-skill-files"),
            ("skills/execute/scripts/run-cascade.sh", "own-skill-files"),
            ("docs/plans/PLAN-my-topic.md", "chain-transitions"),
            ("docs/briefs/BRIEF-my-topic.md", "chain-transitions"),
            ("docs/prds/PRD-my-topic.md", "chain-transitions"),
            ("docs/designs/DESIGN-my-topic.md", "chain-transitions"),
            (
                "docs/designs/current/DESIGN-my-topic.md",
                "chain-transitions",
            ),
            ("docs/roadmaps/ROADMAP-my-topic.md", "chain-transitions"),
            (
                "docs/decisions/DECISION-my-topic-2026-08-15.md",
                "decision-records",
            ),
        ] {
            match wt.classify_path(path) {
                Classification::Inside { class: got, .. } => assert_eq!(got, class, "for {path}"),
                Classification::Outside => panic!("{path} should be inside the set"),
            }
        }
    }

    #[test]
    fn neighbouring_paths_outside_the_set_are_refused() {
        let wt = shipped();
        for path in [
            // Another skill's files, not /execute's own.
            "skills/work-on/SKILL.md",
            // wip scratch that is not keyed on the execute prefix.
            "wip/plan_my-topic_state.md",
            // A doc directory the cascade does not transition.
            "docs/guides/release-notes.md",
            "docs/specs/SPEC-my-topic.md",
            // Repository configuration, the target of incident-shaped writes.
            ".github/workflows/ci.yml",
            "Cargo.toml",
            "README.md",
        ] {
            assert_eq!(
                wt.classify_path(path),
                Classification::Outside,
                "for {path}"
            );
        }
    }

    #[test]
    fn commands_are_classified_by_argv_prefix() {
        let wt = shipped();
        assert!(wt
            .classify_command(&["gh", "pr", "edit", "12", "--body-file", "-"])
            .is_inside());
        assert!(wt
            .classify_command(&["gh", "pr", "ready", "12"])
            .is_inside());
        assert!(wt
            .classify_command(&["gh", "pr", "close", "12"])
            .is_inside());
        // Filing an issue is deliberately outside the set.
        assert_eq!(
            wt.classify_command(&["gh", "issue", "create", "--title", "x"]),
            Classification::Outside
        );
        assert_eq!(
            wt.classify_command(&["gh", "pr", "merge", "12"]),
            Classification::Outside
        );
        assert_eq!(wt.classify_command(&["gh", "pr"]), Classification::Outside);
    }

    #[test]
    fn binding_the_topic_narrows_the_state_and_scratch_class() {
        let wt = shipped();
        let ours = "wip/execute_my-topic_state.md";
        let theirs = "wip/execute_other-topic_state.md";
        assert!(wt.classify_path(theirs).is_inside());
        assert!(wt.classify_path_for_topic(ours, "my-topic").is_inside());
        assert_eq!(
            wt.classify_path_for_topic(theirs, "my-topic"),
            Classification::Outside
        );
        // A class carrying no placeholder is unaffected by the binding.
        assert!(wt
            .classify_path_for_topic("skills/execute/SKILL.md", "my-topic")
            .is_inside());
    }

    #[test]
    fn a_topic_the_placeholder_rejects_matches_nothing_keyed_on_it() {
        let wt = shipped();
        assert_eq!(
            wt.classify_path_for_topic("wip/execute_My_Topic_state.md", "My_Topic"),
            Classification::Outside
        );
    }

    #[test]
    fn traversal_and_absolute_paths_are_outside() {
        let wt = shipped();
        // Folds back inside, so it is inside.
        assert!(wt
            .classify_path("docs/../docs/plans/PLAN-my-topic.md")
            .is_inside());
        // Folds above the root, so it cannot be shown to be inside.
        assert_eq!(
            wt.classify_path("../other-repo/docs/plans/PLAN-x.md"),
            Classification::Outside
        );
        assert_eq!(wt.classify_path("/etc/passwd"), Classification::Outside);
        assert_eq!(wt.classify_path(""), Classification::Outside);
    }

    #[test]
    fn leading_dot_slash_and_doubled_separators_normalize() {
        let wt = shipped();
        assert!(wt
            .classify_path("./docs/plans/PLAN-my-topic.md")
            .is_inside());
        assert!(wt.classify_path("docs//plans/PLAN-my-topic.md").is_inside());
    }

    #[test]
    fn a_declaration_with_an_unknown_schema_is_rejected() {
        let json = r#"{"schema":"write-targets/v2","skill":"execute",
                       "path_classes":[{"id":"x","patterns":["a/*"]}]}"#;
        match parse(json) {
            Err(LoadError::UnsupportedSchema(found)) => assert_eq!(found, "write-targets/v2"),
            Err(other) => panic!("expected an unsupported-schema error, got {other:?}"),
            Ok(_) => panic!("expected an unsupported-schema error, got a declaration"),
        }
    }

    #[test]
    fn malformed_declarations_are_rejected_rather_than_half_read() {
        for json in [
            // Not JSON.
            "{",
            // No schema.
            r#"{"skill":"execute","path_classes":[]}"#,
            // No skill.
            r#"{"schema":"write-targets/v1","path_classes":[]}"#,
            // No classes at all, which would classify everything as outside
            // without saying so.
            r#"{"schema":"write-targets/v1","skill":"execute","path_classes":[]}"#,
            // A class with no patterns.
            r#"{"schema":"write-targets/v1","skill":"execute",
                "path_classes":[{"id":"x","patterns":[]}]}"#,
            // A placeholder that could cross a directory boundary.
            r#"{"schema":"write-targets/v1","skill":"execute","placeholders":{"topic":"[a-z/]+"},
                "path_classes":[{"id":"x","patterns":["wip/{topic}"]}]}"#,
            // A pattern using a placeholder nobody declared.
            r#"{"schema":"write-targets/v1","skill":"execute",
                "path_classes":[{"id":"x","patterns":["wip/{topic}"]}]}"#,
            // An empty argv prefix would match every command.
            r#"{"schema":"write-targets/v1","skill":"execute",
                "path_classes":[{"id":"x","patterns":["a/*"]}],
                "command_classes":[{"id":"c","argv_prefixes":[[]]}]}"#,
        ] {
            assert!(parse(json).is_err(), "should have been rejected: {json}");
        }
    }

    #[test]
    fn a_star_does_not_cross_a_directory_boundary() {
        let placeholders = vec![("topic".to_string(), "[a-z0-9-]+".to_string())];
        let p = compile_glob("docs/*.md", &placeholders).unwrap();
        assert!(p.regex.is_match("docs/a.md"));
        assert!(!p.regex.is_match("docs/nested/a.md"));
        let q = compile_glob("docs/**", &placeholders).unwrap();
        assert!(q.regex.is_match("docs/nested/a.md"));
    }

    #[test]
    fn the_declaration_resolves_from_the_plugin_root() {
        let root = repo_root();
        assert_eq!(
            declaration_path(&root),
            root.join("skills/execute/write-targets.json")
        );
        // The env seam a hook process uses. Set and cleared here rather than
        // read from the ambient environment so the test is self-contained.
        std::env::set_var("CLAUDE_PLUGIN_ROOT", &root);
        let loaded = load_from_plugin_root().expect("loads through CLAUDE_PLUGIN_ROOT");
        assert_eq!(loaded.skill(), "execute");
        std::env::remove_var("CLAUDE_PLUGIN_ROOT");
        assert!(matches!(
            load_from_plugin_root(),
            Err(LoadError::PluginRootUnset)
        ));
    }
}
