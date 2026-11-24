//! The milestone status table: what each roadmap Status word means.
//!
//! `skills/roadmap/references/milestone-statuses.json` is the one authored
//! definition of every milestone status. For each schema family (`v1-v3` and
//! `v4`) it lists the statuses whose behaviour differs from an open milestone,
//! each with its accepted spellings and four properties:
//!
//! - `satisfies`: a dependent may start once this milestone reads it.
//! - `closes`: the milestone needs nothing more for its roadmap to finish.
//! - `takes_work`: a coordinator may still pick the milestone up.
//! - `renders`: whether populate strikes the row, and its diagram class.
//!
//! Any other value (Not started, In progress, a Needs annotation) reads as the
//! table's `open` entry. Every Rust reader that used to compare status words
//! (`table.rs`, FC21 in `checks.rs`, `populate.rs`) asks this module instead,
//! and the coordinate scripts read the same file with jq, so the shell and the
//! binary can't drift apart on what a word means.
//!
//! The file is embedded at build time, unlike the writing-style rules that
//! `rules.rs` loads from disk: a validator running in an adopter's repository
//! has no plugin directory to read, and must not fall back to accepting no
//! status at all. The binary's statuses only change in a release that also
//! ships the scripts, and [`table_version`] lets `shirabe --version` say which
//! table a binary carries.

use std::sync::LazyLock;

use serde_json::Value;

/// The status table as shipped in the roadmap skill's references.
pub const STATUS_TABLE_JSON: &str =
    include_str!("../../../skills/roadmap/references/milestone-statuses.json");

/// The schema value of the roadmap version whose milestones read Completed
/// and Verified.
pub const ROADMAP_V4_SCHEMA: &str = "roadmap/v4";

/// Which entry of the table a roadmap reads: `v4` for a `roadmap/v4`
/// document, `v1-v3` for every other one (v1, v2, v3 and schema-less), which
/// is how every reader behaved before v4 existed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatusFamily {
    V1ToV3,
    V4,
}

impl StatusFamily {
    /// The family a frontmatter `schema:` value reads.
    pub fn of(schema: &str) -> Self {
        if schema == ROADMAP_V4_SCHEMA {
            StatusFamily::V4
        } else {
            StatusFamily::V1ToV3
        }
    }

    /// The key of this family under the file's `schemas` object.
    pub fn key(self) -> &'static str {
        match self {
            StatusFamily::V1ToV3 => "v1-v3",
            StatusFamily::V4 => "v4",
        }
    }
}

/// The four properties of one status.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StatusProps {
    pub satisfies: bool,
    pub closes: bool,
    pub takes_work: bool,
    /// Populate strikes the row through, and the issues-table checks read it
    /// as terminal.
    pub struck: bool,
    /// The diagram class populate gives the node, or `None` when the class is
    /// chosen the way an open milestone's is (ready, blocked or a Needs
    /// class).
    pub class: Option<String>,
}

/// One status of a family: its canonical word, accepted spellings and props.
#[derive(Debug, Clone)]
struct Status {
    word: String,
    spellings: Vec<String>,
    props: StatusProps,
}

/// One allowed move of the `v4` transition list.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Transition {
    pub from: Vec<String>,
    pub to: String,
    pub trigger: String,
}

/// The parsed table.
#[derive(Debug, Clone)]
pub struct StatusTable {
    version: u64,
    v1_v3: Vec<Status>,
    v4: Vec<Status>,
    open_spellings: Vec<String>,
    open: StatusProps,
    transitions_v4: Vec<Transition>,
}

static TABLE: LazyLock<StatusTable> = LazyLock::new(|| {
    StatusTable::parse(STATUS_TABLE_JSON)
        .unwrap_or_else(|e| panic!("embedded milestone-statuses.json is malformed: {e}"))
});

/// The table embedded in this binary.
pub fn table() -> &'static StatusTable {
    &TABLE
}

/// The `version` field of the embedded table.
pub fn table_version() -> u64 {
    table().version
}

/// The properties of `status` on a roadmap at `schema`; shorthand for
/// `table().props(StatusFamily::of(schema), status)`.
pub fn props_for(schema: &str, status: &str) -> StatusProps {
    table().props(StatusFamily::of(schema), status)
}

fn parse_props(v: &Value, what: &str) -> Result<StatusProps, String> {
    let flag = |k: &str| {
        v.get(k)
            .and_then(Value::as_bool)
            .ok_or_else(|| format!("{what}: '{k}' is not a boolean"))
    };
    let renders = v
        .get("renders")
        .ok_or_else(|| format!("{what}: no 'renders'"))?;
    let struck = renders
        .get("struck")
        .and_then(Value::as_bool)
        .ok_or_else(|| format!("{what}: 'renders.struck' is not a boolean"))?;
    let class = match renders.get("class") {
        Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        _ => {
            return Err(format!(
                "{what}: 'renders.class' is neither a string nor null"
            ))
        }
    };
    Ok(StatusProps {
        satisfies: flag("satisfies")?,
        closes: flag("closes")?,
        takes_work: flag("takes_work")?,
        struck,
        class,
    })
}

fn parse_spellings(v: &Value, what: &str) -> Result<Vec<String>, String> {
    v.get("spellings")
        .and_then(Value::as_array)
        .ok_or_else(|| format!("{what}: 'spellings' is not a list"))?
        .iter()
        .map(|s| {
            s.as_str()
                .map(str::to_string)
                .ok_or_else(|| format!("{what}: a spelling is not a string"))
        })
        .collect()
}

fn parse_family(root: &Value, key: &str) -> Result<Vec<Status>, String> {
    let obj = root
        .get("schemas")
        .and_then(|s| s.get(key))
        .and_then(Value::as_object)
        .ok_or_else(|| format!("no 'schemas.{key}' object"))?;
    obj.iter()
        .map(|(word, v)| {
            let what = format!("schemas.{key}.{word}");
            Ok(Status {
                word: word.clone(),
                spellings: parse_spellings(v, &what)?,
                props: parse_props(v, &what)?,
            })
        })
        .collect()
}

impl StatusTable {
    /// Parse a table from its JSON text.
    pub fn parse(json: &str) -> Result<Self, String> {
        let root: Value = serde_json::from_str(json).map_err(|e| e.to_string())?;
        let version = root
            .get("version")
            .and_then(Value::as_u64)
            .ok_or("'version' is not a non-negative integer")?;
        let open = root.get("open").ok_or("no 'open' entry")?;
        let transitions_v4 = root
            .get("transitions")
            .and_then(|t| t.get("v4"))
            .and_then(Value::as_array)
            .ok_or("no 'transitions.v4' list")?
            .iter()
            .map(|t| {
                let s = |k: &str| {
                    t.get(k)
                        .and_then(Value::as_str)
                        .map(str::to_string)
                        .ok_or_else(|| format!("transitions.v4: '{k}' is not a string"))
                };
                let from = t
                    .get("from")
                    .and_then(Value::as_array)
                    .ok_or("transitions.v4: 'from' is not a list")?
                    .iter()
                    .map(|f| {
                        f.as_str().map(str::to_string).ok_or_else(|| {
                            "transitions.v4: a 'from' entry is not a string".to_string()
                        })
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(Transition {
                    from,
                    to: s("to")?,
                    trigger: s("trigger")?,
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        Ok(StatusTable {
            version,
            v1_v3: parse_family(&root, "v1-v3")?,
            v4: parse_family(&root, "v4")?,
            open_spellings: parse_spellings(open, "open")?,
            open: parse_props(open, "open")?,
            transitions_v4,
        })
    }

    fn family(&self, family: StatusFamily) -> &[Status] {
        match family {
            StatusFamily::V1ToV3 => &self.v1_v3,
            StatusFamily::V4 => &self.v4,
        }
    }

    /// The properties of `status` in `family`. The value is trimmed and
    /// matched against each status's spellings ignoring ASCII case, the way
    /// the readers this replaces matched `Done` and `Closed`; anything that
    /// matches no spelling reads as `open`.
    pub fn props(&self, family: StatusFamily, status: &str) -> StatusProps {
        let t = status.trim();
        self.family(family)
            .iter()
            .find(|s| s.spellings.iter().any(|w| w.eq_ignore_ascii_case(t)))
            .map(|s| s.props.clone())
            .unwrap_or_else(|| self.open.clone())
    }

    /// True when `status` is written exactly as one of the family's accepted
    /// spellings or one of the open words (Not started, In progress). FC21
    /// holds a milestone roadmap's Status lines to this set.
    pub fn is_allowed(&self, family: StatusFamily, status: &str) -> bool {
        self.open_spellings.iter().any(|w| w == status)
            || self
                .family(family)
                .iter()
                .any(|s| s.spellings.iter().any(|w| w == status))
    }

    /// The canonical words a milestone of `family` may read, open words
    /// first, in the order a finding names them.
    pub fn canonical_words(&self, family: StatusFamily) -> Vec<String> {
        let mut words = self.open_spellings.clone();
        let mut rest: Vec<&Status> = self.family(family).iter().collect();
        // The JSON object's key order isn't kept by the parser; name the
        // statuses in the order a roadmap moves through them.
        rest.sort_by_key(|s| status_order(&s.word));
        words.extend(rest.into_iter().map(|s| s.word.clone()));
        words
    }

    /// The `v4` transition list.
    pub fn transitions_v4(&self) -> &[Transition] {
        &self.transitions_v4
    }

    /// The table's `version` field.
    pub fn version(&self) -> u64 {
        self.version
    }
}

/// Position of a canonical status word in the order milestones move through.
fn status_order(word: &str) -> usize {
    ["Done", "Completed", "Verified", "Dropped"]
        .iter()
        .position(|w| *w == word)
        .unwrap_or(usize::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(
        satisfies: bool,
        closes: bool,
        takes_work: bool,
        struck: bool,
        class: Option<&str>,
    ) -> StatusProps {
        StatusProps {
            satisfies,
            closes,
            takes_work,
            struck,
            class: class.map(str::to_string),
        }
    }

    #[test]
    fn statuses_v1_v3_properties_match_the_design_table() {
        let t = table();
        let f = StatusFamily::V1ToV3;
        let done = p(true, true, false, true, Some("done"));
        for word in ["Done", "Shipped", "Closed", "done", " closed "] {
            assert_eq!(t.props(f, word), done, "{word}");
        }
        assert_eq!(t.props(f, "Dropped"), p(false, true, false, false, None));
        let open = p(false, false, true, false, None);
        for word in [
            "Not started",
            "In progress",
            "needs-design",
            "",
            "Completed",
            "Verified",
        ] {
            assert_eq!(t.props(f, word), open, "{word}");
        }
    }

    #[test]
    fn statuses_v4_properties_match_the_design_table() {
        let t = table();
        let f = StatusFamily::V4;
        assert_eq!(
            t.props(f, "Completed"),
            p(true, false, false, false, Some("completed"))
        );
        assert_eq!(
            t.props(f, "Verified"),
            p(true, true, false, true, Some("done"))
        );
        assert_eq!(
            t.props(f, "Dropped"),
            p(false, true, false, true, Some("dropped"))
        );
        let open = p(false, false, true, false, None);
        for word in ["Not started", "In progress", "Done", "Shipped", "Closed"] {
            assert_eq!(t.props(f, word), open, "{word}");
        }
    }

    #[test]
    fn statuses_allowed_words_per_family() {
        let t = table();
        for w in [
            "Not started",
            "In progress",
            "Done",
            "Shipped",
            "Closed",
            "Dropped",
        ] {
            assert!(t.is_allowed(StatusFamily::V1ToV3, w), "{w}");
        }
        assert!(!t.is_allowed(StatusFamily::V1ToV3, "Completed"));
        assert!(!t.is_allowed(StatusFamily::V1ToV3, "done"));
        for w in [
            "Not started",
            "In progress",
            "Completed",
            "Verified",
            "Dropped",
        ] {
            assert!(t.is_allowed(StatusFamily::V4, w), "{w}");
        }
        for w in ["Done", "Shipped", "Closed"] {
            assert!(!t.is_allowed(StatusFamily::V4, w), "{w}");
        }
        assert_eq!(
            t.canonical_words(StatusFamily::V1ToV3),
            ["Not started", "In progress", "Done", "Dropped"]
        );
        assert_eq!(
            t.canonical_words(StatusFamily::V4),
            [
                "Not started",
                "In progress",
                "Completed",
                "Verified",
                "Dropped"
            ]
        );
    }

    #[test]
    fn statuses_family_follows_the_schema_line() {
        assert_eq!(StatusFamily::of("roadmap/v4"), StatusFamily::V4);
        for s in ["roadmap/v1", "roadmap/v2", "roadmap/v3", ""] {
            assert_eq!(StatusFamily::of(s), StatusFamily::V1ToV3, "{s}");
        }
    }

    #[test]
    fn statuses_transitions_v4_are_the_design_list() {
        let got: Vec<(Vec<&str>, &str, &str)> = table()
            .transitions_v4()
            .iter()
            .map(|t| {
                (
                    t.from.iter().map(String::as_str).collect(),
                    t.to.as_str(),
                    t.trigger.as_str(),
                )
            })
            .collect();
        assert_eq!(
            got,
            vec![
                (vec!["Not started", "In progress"], "Completed", "finished"),
                (
                    vec!["Not started", "In progress", "Completed"],
                    "Verified",
                    "verified"
                ),
                (
                    vec!["Not started", "In progress", "Completed"],
                    "In progress",
                    "changes-needed"
                ),
                (vec!["Completed", "Verified"], "In progress", "reopen"),
                (
                    vec!["Not started", "In progress", "Completed"],
                    "Dropped",
                    "drop"
                ),
            ]
        );
    }

    /// The embedded copy is the file on disk, and its version is what
    /// `table_version` reports (and `shirabe --version` prints).
    #[test]
    fn statuses_embedded_table_is_the_file_on_disk() {
        let path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../skills/roadmap/references/milestone-statuses.json"
        );
        let on_disk = std::fs::read_to_string(path).expect("read milestone-statuses.json");
        assert_eq!(on_disk, STATUS_TABLE_JSON);
        let v: Value = serde_json::from_str(&on_disk).expect("parse");
        assert_eq!(v["version"].as_u64(), Some(table_version()));
    }

    #[test]
    fn statuses_parse_refuses_a_malformed_table() {
        assert!(StatusTable::parse("{").is_err());
        assert!(StatusTable::parse("{\"version\": \"one\"}").is_err());
        let no_open = STATUS_TABLE_JSON.replace("\"open\"", "\"opened\"");
        assert!(StatusTable::parse(&no_open).is_err());
    }
}
