//! The rule registry, read at hook time.
//!
//! A deny names each broken rule by its registry id and carries the entry's
//! `summary` and the line range its `text` anchors resolve to (PRD R5). The
//! plugin's entry point reads `<plugin root>/references/rule-registry.json`,
//! so the deny carries the text of the plugin the agent is using; the legacy
//! `shirabe pr-body-hook` has no plugin root and reads the copies compiled
//! into the binary, naming the file by its repository-relative path (R11).
//!
//! Ranges resolve the way `scripts/rule-registry.sh range` resolves them: the
//! first anchor must occur on exactly one line, and the last anchor is the
//! first line at or after it that contains it (the first line itself when
//! there is no last anchor), compared as bytes. A test holds the two readers
//! to the same answer. Fields this reader doesn't know are ignored, so a newer
//! registry doesn't break an older binary.

use std::path::{Path, PathBuf};

/// The registry and the conformance reference, compiled in for the legacy
/// entry point. The crate is never published, so the paths outside it hold.
const EMBEDDED_REGISTRY: &str = include_str!("../../../../references/rule-registry.json");
const EMBEDDED_FILES: &[(&str, &str)] = &[(
    "references/pr-body-conformance.md",
    include_str!("../../../../references/pr-body-conformance.md"),
)];

/// Where a registry was read from, which decides how its rule files are read
/// and how the deny names them.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RegistrySource {
    /// A plugin root: files are read under it and named by absolute path.
    PluginRoot(PathBuf),
    /// The copies compiled into the binary, named by repository-relative path.
    Embedded,
}

/// One registry entry, as far as the hook needs it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub id: String,
    pub status: String,
    pub summary: String,
    pub aliases: Vec<String>,
    text: Option<TextRef>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct TextRef {
    path: String,
    first: String,
    last: String,
}

/// Where a rule's full text is: the file as the deny names it, and its lines.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RuleRange {
    pub path: String,
    pub first: usize,
    pub last: usize,
}

/// Why the registry can't answer for a rule (PRD R7 case 6). `id` is the rule
/// asked about, or empty when the registry itself can't be read.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RegistryError {
    pub id: String,
    pub what: String,
}

impl RegistryError {
    fn new(id: &str, what: impl Into<String>) -> Self {
        RegistryError {
            id: id.to_string(),
            what: what.into(),
        }
    }
}

#[derive(Clone, Debug)]
pub struct Registry {
    source: RegistrySource,
    /// The plugin root, resolved, for [`RegistrySource::PluginRoot`].
    root: Option<PathBuf>,
    entries: Vec<Entry>,
}

impl Registry {
    /// Read the registry of the plugin at `dir`.
    pub fn from_plugin_root(dir: &Path) -> Result<Self, RegistryError> {
        let root = std::fs::canonicalize(dir).map_err(|e| {
            RegistryError::new(
                "",
                format!("the plugin root {} can't be read: {e}", dir.display()),
            )
        })?;
        let file = root.join("references").join("rule-registry.json");
        let json = std::fs::read_to_string(&file).map_err(|e| {
            RegistryError::new("", format!("{} can't be read: {e}", file.display()))
        })?;
        let mut reg = Self::parse(&json, RegistrySource::PluginRoot(dir.to_path_buf()))?;
        reg.root = Some(root);
        Ok(reg)
    }

    /// The registry compiled into the binary.
    pub fn embedded() -> Result<Self, RegistryError> {
        Self::parse(EMBEDDED_REGISTRY, RegistrySource::Embedded)
    }

    /// Read a registry from `source`.
    pub fn load(source: &RegistrySource) -> Result<Self, RegistryError> {
        match source {
            RegistrySource::PluginRoot(dir) => Self::from_plugin_root(dir),
            RegistrySource::Embedded => Self::embedded(),
        }
    }

    fn parse(json: &str, source: RegistrySource) -> Result<Self, RegistryError> {
        let v: serde_json::Value = serde_json::from_str(json)
            .map_err(|e| RegistryError::new("", format!("the registry doesn't parse: {e}")))?;
        let rules = v
            .get("rules")
            .and_then(|r| r.as_array())
            .ok_or_else(|| RegistryError::new("", "the registry has no rules list"))?;
        let s = |e: &serde_json::Value, k: &str| {
            e.get(k)
                .and_then(|x| x.as_str())
                .unwrap_or_default()
                .to_string()
        };
        let entries = rules
            .iter()
            .map(|e| Entry {
                id: s(e, "id"),
                status: s(e, "status"),
                summary: s(e, "summary"),
                aliases: e
                    .get("aliases")
                    .and_then(|a| a.as_array())
                    .map(|a| {
                        a.iter()
                            .filter_map(|x| x.as_str().map(str::to_string))
                            .collect()
                    })
                    .unwrap_or_default(),
                text: e.get("text").map(|t| TextRef {
                    path: s(t, "path"),
                    first: s(t, "first"),
                    last: s(t, "last"),
                }),
            })
            .collect();
        Ok(Registry {
            source,
            root: None,
            entries,
        })
    }

    /// The active entry `id`. Unknown, retired, without a valid status, or
    /// listed twice, as `rule-registry.sh` refuses.
    pub fn entry(&self, id: &str) -> Result<&Entry, RegistryError> {
        let mut found = self.entries.iter().filter(|e| e.id == id);
        let e = found
            .next()
            .ok_or_else(|| RegistryError::new(id, "the registry has no entry for it"))?;
        if found.next().is_some() {
            return Err(RegistryError::new(id, "the registry lists it twice"));
        }
        match e.status.as_str() {
            "active" => Ok(e),
            "retired" => Err(RegistryError::new(id, "the registry lists it as retired")),
            _ => Err(RegistryError::new(
                id,
                "its registry entry has no valid status",
            )),
        }
    }

    /// The active entry whose `aliases` holds `code`.
    pub fn by_alias(&self, code: &str) -> Option<&Entry> {
        self.entries
            .iter()
            .find(|e| e.status == "active" && e.aliases.iter().any(|a| a == code))
    }

    /// The entry's position in the registry, which orders a deny's blocks.
    pub fn order(&self, id: &str) -> usize {
        self.entries
            .iter()
            .position(|e| e.id == id)
            .unwrap_or(usize::MAX)
    }

    /// Where `entry`'s text is.
    pub fn range(&self, entry: &Entry) -> Result<RuleRange, RegistryError> {
        let id = entry.id.as_str();
        let t = entry
            .text
            .as_ref()
            .ok_or_else(|| RegistryError::new(id, "its registry entry has no text"))?;
        if t.first.is_empty() {
            return Err(RegistryError::new(
                id,
                "its registry entry has no first anchor",
            ));
        }
        let (shown, content) = self.read_text(id, &t.path)?;
        let (first, last) = anchor_range(&content, t.first.as_bytes(), t.last.as_bytes())
            .map_err(|why| RegistryError::new(id, format!("{why} in {}", t.path)))?;
        Ok(RuleRange {
            path: shown,
            first,
            last,
        })
    }

    /// Read a rule file named by a registry path: the name the deny shows,
    /// and the file's bytes.
    fn read_text(&self, id: &str, rel: &str) -> Result<(String, Vec<u8>), RegistryError> {
        if !safe_shape(rel) {
            return Err(RegistryError::new(
                id,
                format!("its text path {rel:?} is unsafe"),
            ));
        }
        match &self.source {
            RegistrySource::Embedded => EMBEDDED_FILES
                .iter()
                .find(|(p, _)| *p == rel)
                .map(|(p, c)| (p.to_string(), c.as_bytes().to_vec()))
                .ok_or_else(|| {
                    RegistryError::new(id, format!("its text {rel} isn't built into the binary"))
                }),
            RegistrySource::PluginRoot(_) => {
                let root = self.root.as_deref().unwrap_or(Path::new("/nonexistent"));
                let full = safe_path(root, rel).ok_or_else(|| {
                    RegistryError::new(id, format!("its text path {rel} is unsafe or missing"))
                })?;
                let bytes = std::fs::read(&full).map_err(|e| {
                    RegistryError::new(id, format!("{} can't be read: {e}", full.display()))
                })?;
                Ok((full.display().to_string(), bytes))
            }
        }
    }
}

/// The shape `rule-registry.sh`'s `safe_path` allows: a relative path of
/// ordinary characters with no `.` or `..` segment.
fn safe_shape(p: &str) -> bool {
    let mut chars = p.chars();
    let first_ok = chars
        .next()
        .is_some_and(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_');
    first_ok
        && p.chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '/' | '-'))
        && !p.split('/').any(|seg| seg == "." || seg == "..")
}

/// `safe_path` from `rule-registry.sh`: the absolute file when `rel` isn't a
/// symlink and is a regular file whose directory resolves under `root`.
fn safe_path(root: &Path, rel: &str) -> Option<PathBuf> {
    let full = root.join(rel);
    let meta = std::fs::symlink_metadata(&full).ok()?;
    if !meta.file_type().is_file() {
        return None;
    }
    let dir = std::fs::canonicalize(full.parent()?).ok()?;
    if !dir.starts_with(root) {
        return None;
    }
    Some(dir.join(full.file_name()?))
}

/// The range `rule-registry.sh range` prints: the one line holding `first`,
/// and the first line at or after it holding `last` (or the first line
/// itself when `last` is empty). Lines are awk's records, split on `\n`.
fn anchor_range(content: &[u8], first: &[u8], last: &[u8]) -> Result<(usize, usize), String> {
    let lines: Vec<&[u8]> = {
        let mut v: Vec<&[u8]> = content.split(|b| *b == b'\n').collect();
        if content.ends_with(b"\n") {
            v.pop();
        }
        v
    };
    let holds = |line: &[u8], pat: &[u8]| line.windows(pat.len()).any(|w| w == pat);
    let firsts: Vec<usize> = lines
        .iter()
        .enumerate()
        .filter(|(_, l)| holds(l, first))
        .map(|(i, _)| i)
        .collect();
    if firsts.len() != 1 {
        return Err("its first anchor is not on exactly one line".to_string());
    }
    let a = firsts[0];
    if last.is_empty() {
        return Ok((a + 1, a + 1));
    }
    match lines[a..].iter().position(|l| holds(l, last)) {
        Some(off) => Ok((a + 1, a + off + 1)),
        None => Err("its last anchor is not at or after its first".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn repo_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
    }

    /// A scratch plugin root holding `registry` and the conformance reference.
    fn fixture(name: &str, registry: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("shirabe-registry-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("references")).unwrap();
        std::fs::write(dir.join("references/rule-registry.json"), registry).unwrap();
        std::fs::copy(
            repo_root().join("references/pr-body-conformance.md"),
            dir.join("references/pr-body-conformance.md"),
        )
        .unwrap();
        dir
    }

    #[test]
    fn resolves_ids_and_aliases_from_the_embedded_copy() {
        let reg = Registry::embedded().unwrap();
        let e = reg.entry("pr-body/one-separator").unwrap();
        assert!(e.summary.contains("separator"));
        assert_eq!(reg.by_alias("PB2").unwrap().id, "pr-body/one-separator");
        assert_eq!(
            reg.by_alias("PB4").unwrap().id,
            "pr-body/no-heading-in-part1"
        );
        assert!(reg.by_alias("PB9").is_none());
        let r = reg.range(e).unwrap();
        assert_eq!(r.path, "references/pr-body-conformance.md");
        assert!(r.first <= r.last);
    }

    #[test]
    fn the_plugin_root_names_the_file_by_absolute_path() {
        let reg = Registry::from_plugin_root(&repo_root()).unwrap();
        let r = reg
            .range(reg.entry("commit/no-ai-trailer").unwrap())
            .unwrap();
        assert!(Path::new(&r.path).is_absolute(), "{}", r.path);
        assert!(r.path.ends_with("/references/pr-body-conformance.md"));
    }

    /// The reader and `scripts/rule-registry.sh range` agree on every entry
    /// the hook can name.
    #[test]
    fn ranges_match_the_shell_reader() {
        let root = repo_root();
        let reg = Registry::from_plugin_root(&root).unwrap();
        let embedded = Registry::embedded().unwrap();
        let ids: Vec<String> = reg
            .entries
            .iter()
            .filter(|e| e.id.starts_with("pr-body/") || e.id.starts_with("commit/"))
            .map(|e| e.id.clone())
            .collect();
        assert!(ids.len() >= 6, "{ids:?}");
        for id in ids {
            let out = std::process::Command::new("bash")
                .arg(root.join("scripts/rule-registry.sh"))
                .args(["range", &id])
                .output()
                .expect("bash runs");
            assert!(
                out.status.success(),
                "{id}: {}",
                String::from_utf8_lossy(&out.stderr)
            );
            let shell = String::from_utf8_lossy(&out.stdout).trim().to_string();
            let r = reg.range(reg.entry(&id).unwrap()).unwrap();
            assert_eq!(format!("{} {}", r.first, r.last), shell, "{id}");
            let e = embedded.range(embedded.entry(&id).unwrap()).unwrap();
            assert_eq!((e.first, e.last), (r.first, r.last), "{id} embedded");
        }
    }

    #[test]
    fn anchor_rules_follow_the_shell_reader() {
        let text = b"a\nfirst x\nmid last\nlast\n";
        assert_eq!(anchor_range(text, b"first", b"last"), Ok((2, 3)));
        assert_eq!(anchor_range(text, b"first", b""), Ok((2, 2)));
        assert_eq!(
            anchor_range(text, b"first x", b"x"),
            Ok((2, 2)),
            "same line"
        );
        assert!(anchor_range(text, b"last", b"").is_err(), "two lines");
        assert!(anchor_range(text, b"nope", b"").is_err());
        assert!(
            anchor_range(text, b"mid", b"first").is_err(),
            "last before first"
        );
    }

    #[test]
    fn refuses_unknown_retired_and_doubled_entries() {
        let dir = fixture(
            "status",
            r#"{"rules": [
                {"id": "a/b", "status": "retired"},
                {"id": "c/d", "status": "active"}, {"id": "c/d", "status": "active"},
                {"id": "e/f"},
                {"id": "g/h", "status": "active", "summary": "s", "new_field": {"x": 1},
                 "text": {"path": "../etc/passwd", "first": "x"}}
            ]}"#,
        );
        let reg = Registry::from_plugin_root(&dir).unwrap();
        assert!(reg.entry("x/y").unwrap_err().what.contains("no entry"));
        assert!(reg.entry("a/b").unwrap_err().what.contains("retired"));
        assert!(reg.entry("c/d").unwrap_err().what.contains("twice"));
        assert!(reg.entry("e/f").unwrap_err().what.contains("status"));
        let g = reg.entry("g/h").expect("unknown fields are ignored");
        let err = reg.range(g).unwrap_err();
        assert_eq!(err.id, "g/h");
        assert!(err.what.contains("unsafe"), "{}", err.what);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn refuses_unsafe_paths() {
        for p in ["/etc/passwd", "a/../b", "./a", "a/./b", "-a", "a b", "a\\b"] {
            assert!(!safe_shape(p), "{p}");
        }
        assert!(safe_shape("references/pr-body-conformance.md"));
        #[cfg(unix)]
        {
            let dir = fixture(
                "symlink",
                r#"{"rules": [{"id": "a/b", "status": "active",
                   "text": {"path": "references/link.md", "first": "PB2"}}]}"#,
            );
            std::os::unix::fs::symlink(
                dir.join("references/pr-body-conformance.md"),
                dir.join("references/link.md"),
            )
            .unwrap();
            let reg = Registry::from_plugin_root(&dir).unwrap();
            let err = reg.range(reg.entry("a/b").unwrap()).unwrap_err();
            assert!(err.what.contains("unsafe"), "{}", err.what);
            let _ = std::fs::remove_dir_all(&dir);
        }
    }

    #[test]
    fn an_unreadable_registry_is_an_error() {
        let dir =
            std::env::temp_dir().join(format!("shirabe-registry-none-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        assert!(Registry::from_plugin_root(&dir).is_err());
        let bad = fixture("bad", "not json");
        assert!(Registry::from_plugin_root(&bad).is_err());
        let _ = std::fs::remove_dir_all(&dir);
        let _ = std::fs::remove_dir_all(&bad);
    }
}
