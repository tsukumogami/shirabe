//! `shirabe roadmap migrate` -- move a `roadmap/v2` or `roadmap/v3` roadmap
//! to `roadmap/v4`.
//!
//! On v4 a milestone whose work has landed reads Completed and one a verdict
//! has checked reads Verified, where v2 and v3 have the single Done (spelled
//! Done, Shipped or Closed). The migration maps each such milestone by its
//! latest verdict line in `## Progress` -- the last
//! `- <date>: <milestone> -- <verdict>` line naming it, `Feature N` read as
//! `Milestone N` -- to Verified when that verdict is verified or verified
//! with follow-ups, and to Completed otherwise. Every other status is kept.
//! A v2 roadmap's `## Features` layout becomes `## Milestones` with
//! `### Milestone N:` headings and Milestone words in its Dependencies lines.
//!
//! The checks run in this order, each refusing with a non-zero exit and the
//! file unchanged: the path must resolve inside the repository the command
//! runs in; a file already on `roadmap/v4` exits 0 saying so; a `roadmap/v1`
//! or schema-less file is refused naming its schema; a roadmap whose own
//! status is Done is refused; and a milestone block it can't parse is refused
//! naming it.
//!
//! Security invariants:
//!
//! - Text copied from the roadmap into the output is limited to milestone tags
//!   and lines matching the fixed verdict pattern, with control characters
//!   removed before printing.
//! - The write goes through a temporary file created exclusively
//!   (`create_new`) under an unpredictable name in the roadmap's directory,
//!   then renamed over the original, so a failure leaves the original
//!   untouched and a file planted at a guessable name is never followed or
//!   overwritten.

use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::LazyLock;

use regex::Regex;
use shirabe_validate::features::{is_milestone_heading, RoadmapVersion};
use shirabe_validate::statuses::{self, StatusFamily, ROADMAP_V4_SCHEMA};
use shirabe_validate::{
    detect_format, formats, is_notice, parse_doc_bytes, resolve_doc_visibility, validate_file,
    Config, ReviewPosture,
};

/// Clap-parsed args for `shirabe roadmap migrate`.
#[derive(clap::Args, Debug)]
pub struct MigrateArgs {
    /// Path to the roadmap to migrate. It must resolve inside the repository
    /// the command runs in.
    pub roadmap_path: String,

    /// Print what each milestone would become and write nothing.
    #[arg(long = "dry-run")]
    pub dry_run: bool,
}

/// The verdict lines the migration reads, and the only roadmap text besides a
/// milestone tag it copies into its output.
static VERDICT_LINE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^- [0-9]{4}-[0-9]{2}-[0-9]{2}: (?:Feature|Milestone) ([0-9]+) -- (verified with follow-ups|verified|changes needed)\b",
    )
    .expect("verdict pattern compiles")
});

/// A `Feature N` (or `Features N, M`) reference in a Dependencies line, which
/// a v3 or v4 roadmap spells with the Milestone word.
static FEATURE_REF: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\bFeature(s?) ([0-9])").expect("feature pattern compiles"));

/// Entry point used by `main.rs`.
pub fn run(args: &MigrateArgs) -> ExitCode {
    match run_inner(args) {
        Ok(lines) => {
            for line in lines {
                println!("{}", line);
            }
            ExitCode::SUCCESS
        }
        Err(err) => {
            let clean: Vec<String> = err.lines().map(strip_controls).collect();
            eprintln!("error: {}", clean.join("\n"));
            ExitCode::FAILURE
        }
    }
}

fn run_inner(args: &MigrateArgs) -> Result<Vec<String>, String> {
    let given = Path::new(&args.roadmap_path);
    let target = resolve_inside_repo(given)?;
    let shown = args.roadmap_path.as_str();

    let bytes = fs::read(&target).map_err(|e| format!("read {}: {}", shown, e))?;
    let text =
        String::from_utf8(bytes.clone()).map_err(|_| format!("{} is not UTF-8 text", shown))?;
    let target_str = target.to_string_lossy().to_string();
    let doc = parse_doc_bytes(&target_str, &bytes)
        .map_err(|e| format!("can't parse {}: {}", shown, e))?;

    if doc.schema == ROADMAP_V4_SCHEMA {
        return Ok(vec!["already roadmap/v4".to_string()]);
    }
    let version = match RoadmapVersion::of(&doc.schema) {
        v @ (RoadmapVersion::V2 | RoadmapVersion::V3) if !doc.schema.is_empty() => v,
        _ => {
            return Err(if doc.schema.is_empty() {
                format!(
                    "{} has no schema; only a roadmap/v2 or roadmap/v3 roadmap is migrated",
                    shown
                )
            } else {
                format!(
                    "{} is {}; only a roadmap/v2 or roadmap/v3 roadmap is migrated",
                    shown, doc.schema
                )
            })
        }
    };
    if doc.status.trim() == "Done" {
        return Err(format!(
            "{} has status Done; a finished roadmap isn't migrated",
            shown
        ));
    }

    let plan = plan_migration(&text, version)?;
    let output = plan.report();

    if args.dry_run {
        return Ok(output);
    }

    check_result(&target, &plan.text)?;
    write_atomically(&target, plan.text.as_bytes())?;
    Ok(output)
}

/// Resolve `given` and refuse it unless it is a regular file inside the
/// repository holding the current directory. Symlinks are resolved first, so
/// a link inside the repository pointing out of it is refused too.
fn resolve_inside_repo(given: &Path) -> Result<PathBuf, String> {
    let shown = given.display();
    let target = fs::canonicalize(given).map_err(|e| format!("read {}: {}", shown, e))?;
    if !target.is_file() {
        return Err(format!("{} is not a file", shown));
    }
    let cwd = std::env::current_dir()
        .and_then(fs::canonicalize)
        .map_err(|e| format!("read the current directory: {}", e))?;
    let root = cwd
        .ancestors()
        .find(|d| d.join(".git").exists())
        .ok_or_else(|| {
            format!(
                "{} can't be checked: the current directory isn't inside a git repository",
                shown
            )
        })?;
    if !target.starts_with(root) {
        return Err(format!(
            "{} is outside the repository this runs in ({})",
            shown,
            root.display()
        ));
    }
    Ok(target)
}

/// One milestone's move.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Move {
    /// The tag the milestone reads after migration (`Milestone 2`, `AB3`).
    tag: String,
    old: String,
    new: String,
    /// The latest verdict line naming the milestone, without its newline.
    verdict_line: Option<String>,
}

/// The migrated text and the per-milestone moves it makes.
#[derive(Debug)]
struct Plan {
    text: String,
    moves: Vec<Move>,
}

impl Plan {
    fn report(&self) -> Vec<String> {
        self.moves
            .iter()
            .map(|m| {
                let why = m.verdict_line.as_deref().unwrap_or("no verdict line");
                strip_controls(&format!("{}: {} -> {} ({})", m.tag, m.old, m.new, why))
            })
            .collect()
    }
}

/// Remove every control character (newlines, carriage returns, escapes).
fn strip_controls(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).collect()
}

/// The text of `line` without its line ending.
fn bare(line: &str) -> &str {
    let l = line.strip_suffix('\n').unwrap_or(line);
    l.strip_suffix('\r').unwrap_or(l)
}

/// The line ending `line` carries.
fn ending(line: &str) -> &str {
    &line[bare(line).len()..]
}

/// The `[start, end)` line range of the `## <name>` section's body.
fn section_range(lines: &[String], name: &str) -> Option<(usize, usize)> {
    let heading = format!("## {}", name);
    let at = lines.iter().position(|l| bare(l).trim_end() == heading)?;
    let end = lines[at + 1..]
        .iter()
        .position(|l| l.starts_with("## "))
        .map_or(lines.len(), |p| at + 1 + p);
    Some((at + 1, end))
}

/// The number of a classic `Feature N` or `Milestone N` tag, as written.
fn classic_number(tag: &str) -> Option<&str> {
    tag.strip_prefix("Milestone ")
        .or_else(|| tag.strip_prefix("Feature "))
        .filter(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
}

/// The latest verdict line per classic milestone number in `## Progress`.
fn latest_verdicts(lines: &[String]) -> HashMap<String, (String, String)> {
    let mut out = HashMap::new();
    let Some((start, end)) = section_range(lines, "Progress") else {
        return out;
    };
    for line in &lines[start..end] {
        let text = bare(line);
        if let Some(c) = VERDICT_LINE.captures(text) {
            out.insert(c[1].to_string(), (c[2].to_string(), text.to_string()));
        }
    }
    out
}

/// Work out the migrated text of a v2 or v3 roadmap, or refuse it.
fn plan_migration(text: &str, version: RoadmapVersion) -> Result<Plan, String> {
    let mut lines: Vec<String> = text.split_inclusive('\n').map(str::to_string).collect();

    // The frontmatter's schema line.
    if lines.first().map(|l| bare(l)) != Some("---") {
        return Err("the frontmatter can't be found".to_string());
    }
    let fm_end = lines[1..]
        .iter()
        .position(|l| bare(l) == "---")
        .map(|p| p + 1)
        .ok_or("the frontmatter isn't closed")?;
    let schema_at = (1..fm_end)
        .find(|&i| bare(&lines[i]).starts_with("schema:"))
        .ok_or("the frontmatter has no schema line")?;
    let eol = ending(&lines[schema_at]).to_string();
    lines[schema_at] = format!("schema: {}{}", ROADMAP_V4_SCHEMA, eol);

    let section = version.items_section();
    let (start, end) = section_range(&lines, section)
        .ok_or_else(|| format!("the roadmap has no ## {} section", section))?;
    if version == RoadmapVersion::V2 && section_range(&lines, "Milestones").is_some() {
        return Err(
            "the roadmap already has a ## Milestones section, so ## Features can't be renamed to it"
                .to_string(),
        );
    }

    // The milestone blocks: (heading index, end index) pairs.
    let mut blocks: Vec<(usize, usize)> = Vec::new();
    for (i, raw) in lines.iter().enumerate().take(end).skip(start) {
        let line = bare(raw);
        if !line.starts_with("### ") {
            continue;
        }
        if !is_milestone_heading(line, version) {
            return Err(format!(
                "can't parse the milestone block at line {}: '{}' isn't a milestone heading",
                i + 1,
                line
            ));
        }
        if let Some(last) = blocks.last_mut() {
            last.1 = i;
        }
        blocks.push((i, end));
    }
    if blocks.is_empty() {
        return Err(format!("no milestones found under ## {}", section));
    }

    let verdicts = latest_verdicts(&lines);
    let table = statuses::table();
    let mut moves = Vec::new();
    let mut status_lines = Vec::new();

    for &(head, stop) in &blocks {
        let heading = bare(&lines[head]).to_string();
        let old_tag = heading["### ".len()..]
            .split(':')
            .next()
            .unwrap_or_default()
            .to_string();
        let statuses: Vec<usize> = (head + 1..stop)
            .filter(|&i| lines[i].starts_with("**Status:**"))
            .collect();
        let at = match statuses.as_slice() {
            [one] => *one,
            [] => {
                return Err(format!(
                    "can't parse the milestone block '{}': it has no **Status:** line",
                    old_tag
                ))
            }
            _ => {
                return Err(format!(
                    "can't parse the milestone block '{}': it has {} **Status:** lines",
                    old_tag,
                    statuses.len()
                ))
            }
        };
        let old = bare(&lines[at])["**Status:**".len()..].trim().to_string();
        if !table.is_allowed(StatusFamily::V1ToV3, &old) {
            return Err(format!(
                "can't parse the milestone block '{}': its Status '{}' isn't a {} status",
                old_tag,
                old,
                version_name(version)
            ));
        }

        let verdict = classic_number(&old_tag).and_then(|n| verdicts.get(n));
        // Done, Shipped and Closed are the only v1-v3 statuses that satisfy.
        let new = if table.props(StatusFamily::V1ToV3, &old).satisfies {
            match verdict {
                Some((v, _)) if v.starts_with("verified") => "Verified".to_string(),
                _ => "Completed".to_string(),
            }
        } else {
            old.clone()
        };

        let new_tag = match (version, classic_number(&old_tag)) {
            (RoadmapVersion::V2, Some(n)) => format!("Milestone {}", n),
            _ => old_tag.clone(),
        };
        if new_tag != old_tag {
            let eol = ending(&lines[head]).to_string();
            let rest = &heading["### ".len() + old_tag.len()..];
            lines[head] = format!("### {}{}{}", new_tag, rest, eol);
        }
        if version == RoadmapVersion::V2 {
            for line in &mut lines[head + 1..stop] {
                if line.starts_with("**Dependencies:**") {
                    *line = FEATURE_REF
                        .replace_all(line, "Milestone${1} ${2}")
                        .into_owned();
                }
            }
        }
        if new != old {
            let eol = ending(&lines[at]).to_string();
            lines[at] = format!("**Status:** {}{}", new, eol);
        }
        status_lines.push((old_tag.clone(), old.clone(), new.clone()));
        moves.push(Move {
            tag: new_tag,
            old,
            new,
            verdict_line: verdict.map(|(_, line)| line.clone()),
        });
    }

    if version == RoadmapVersion::V2 {
        lines[start - 1] = format!("## Milestones{}", ending(&lines[start - 1]));
        rename_issues_key_column(&mut lines);
    }

    for (tag, old, new) in &status_lines {
        if old != new {
            write_progress_row(&mut lines, tag, new);
        }
    }

    Ok(Plan {
        text: lines.concat(),
        moves,
    })
}

fn version_name(version: RoadmapVersion) -> &'static str {
    match version {
        RoadmapVersion::V2 => "roadmap/v2",
        _ => "roadmap/v3",
    }
}

/// True when a Progress-table first cell names the milestone `tag`: the tag
/// (or its `Feature N`/`Milestone N` twin) followed by the cell's end, a
/// colon or whitespace. Mirrors the validator's reading of the row.
fn row_names(item: &str, tag: &str) -> bool {
    let item = item.strip_prefix('[').unwrap_or(item);
    let twin = classic_number(tag).map(|n| {
        if tag.starts_with("Milestone ") {
            format!("Feature {}", n)
        } else {
            format!("Milestone {}", n)
        }
    });
    std::iter::once(tag.to_string())
        .chain(twin)
        .any(|t| match item.strip_prefix(t.as_str()) {
            Some(rest) => rest
                .chars()
                .next()
                .is_none_or(|c| c == ':' || c.is_whitespace()),
            None => false,
        })
}

/// Cells of a pipe row, outer pipes removed, untrimmed.
fn row_cells(line: &str) -> Option<Vec<String>> {
    let t = line.trim();
    let inner = t.strip_prefix('|')?;
    let inner = inner.strip_suffix('|').unwrap_or(inner);
    Some(inner.split('|').map(str::to_string).collect())
}

fn is_pipe_row(line: &str) -> bool {
    let t = line.trim();
    t.starts_with('|') && t.matches('|').count() >= 2
}

fn is_separator(line: &str) -> bool {
    is_pipe_row(line)
        && row_cells(line).is_some_and(|cells| {
            cells.iter().all(|c| {
                let c = c.trim();
                !c.is_empty() && c.chars().all(|r| r == '-' || r == ':')
            })
        })
}

/// Set the Status cell of `tag`'s row in the Progress table -- the first
/// table under `## Progress` whose header has a `Status` column -- to `new`.
/// A roadmap without that table, or a milestone without a row, is left
/// alone, as the validator leaves it.
fn write_progress_row(lines: &mut [String], tag: &str, new: &str) {
    let Some((start, end)) = section_range(lines, "Progress") else {
        return;
    };
    let mut i = start;
    while i < end {
        let header = bare(&lines[i]);
        if !(is_pipe_row(header) && i + 1 < end && is_separator(bare(&lines[i + 1]))) {
            i += 1;
            continue;
        }
        let columns = row_cells(header).unwrap_or_default();
        let mut j = i + 2;
        while j < end && is_pipe_row(bare(&lines[j])) {
            j += 1;
        }
        let Some(col) = columns.iter().position(|c| c.trim() == "Status") else {
            i = j;
            continue;
        };
        for line in &mut lines[i + 2..j] {
            let row = bare(line).to_string();
            let Some(mut cells) = row_cells(&row) else {
                continue;
            };
            if !row_names(cells[0].trim(), tag) || col >= cells.len() {
                continue;
            }
            cells[col] = format!(" {} ", new);
            let indent = &row[..row.len() - row.trim_start().len()];
            let eol = ending(line).to_string();
            *line = format!("{}|{}|{}", indent, cells.join("|"), eol);
        }
        return;
    }
}

/// On a v2 roadmap the Implementation Issues table's key column reads
/// `Feature`; the v3 layout v4 shares reads `Milestone`. Rename the header
/// cell of the section's first table when it is `Feature`.
fn rename_issues_key_column(lines: &mut [String]) {
    let Some((start, end)) = section_range(lines, "Implementation Issues") else {
        return;
    };
    let Some(i) = (start..end).find(|&i| is_pipe_row(bare(&lines[i]))) else {
        return;
    };
    let row = bare(&lines[i]).to_string();
    let Some(mut cells) = row_cells(&row) else {
        return;
    };
    if cells[0].trim() != "Feature" {
        return;
    }
    cells[0] = cells[0].replacen("Feature", "Milestone", 1);
    let eol = ending(&lines[i]).to_string();
    lines[i] = format!("|{}|{}", cells.join("|"), eol);
}

/// Validate the migrated text as the roadmap it will become, and refuse it
/// on any error-level finding.
fn check_result(target: &Path, text: &str) -> Result<(), String> {
    let path = target.to_string_lossy().to_string();
    let doc = parse_doc_bytes(&path, text.as_bytes())
        .map_err(|e| format!("the migrated roadmap can't be parsed: {}", e))?;
    let base = target
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    let spec = detect_format(&base)
        .or_else(|| formats().into_iter().find(|s| s.prefix == "ROADMAP-"))
        .ok_or("no roadmap format is known to the validator")?;
    let cfg = Config {
        custom_statuses: HashMap::new(),
        visibility: resolve_doc_visibility(target),
        allow_untracked_acs: false,
    };
    let errors: Vec<String> = validate_file(&doc, &spec, &cfg)
        .into_iter()
        .filter(|e| !is_notice(e, ReviewPosture::Draft))
        .map(|e| format!("[{}] {}", e.code, e.message))
        .collect();
    if errors.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "the migrated roadmap fails validation, so nothing was written:\n{}",
            errors.join("\n")
        ))
    }
}

/// Write `contents` over `target` through an exclusively created temporary
/// file with an unpredictable name in the same directory, then rename it
/// over the original. Any failure removes the temporary file and leaves the
/// original as it was.
fn write_atomically(target: &Path, contents: &[u8]) -> Result<(), String> {
    let dir = target
        .parent()
        .ok_or_else(|| format!("{} has no parent directory", target.display()))?;
    let base = target
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    let mut nonce = [0u8; 16];
    getrandom::getrandom(&mut nonce).map_err(|e| format!("generate a temporary name: {}", e))?;
    let hex: String = nonce.iter().map(|b| format!("{:02x}", b)).collect();
    let temp = dir.join(format!(".{}.migrate-{}.tmp", base, hex));

    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&temp).map_err(|e| {
        format!(
            "create a temporary file in {}: {}; the roadmap is unchanged",
            dir.display(),
            e
        )
    })?;
    let result = file
        .write_all(contents)
        .and_then(|()| file.sync_all())
        .and_then(|()| {
            let perms = fs::metadata(target)?.permissions();
            fs::set_permissions(&temp, perms)
        })
        .and_then(|()| fs::rename(&temp, target));
    drop(file);
    if let Err(e) = result {
        let _ = fs::remove_file(&temp);
        return Err(format!(
            "write {}: {}; the roadmap is unchanged",
            target.display(),
            e
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const V3: &str = "---\nschema: roadmap/v3\nstatus: Active\n---\n\n# ROADMAP: x\n\n## Milestones\n\n### Milestone 1: A\n\n**Dependencies:** None\n**Status:** Done\n\n### Milestone 2: B\n\n**Dependencies:** Milestone 1\n**Status:** Not started\n\n## Progress\n\n| Milestone | Status | Verdict |\n|---|---|---|\n| Milestone 1: A | ~~Done~~ | -- |\n| Milestone 12: L | Done | -- |\n\n- 2026-01-02: Feature 1 -- verified, checked by c\n";

    #[test]
    fn verdict_pattern_takes_the_three_verdicts_only() {
        let c = VERDICT_LINE
            .captures("- 2026-01-02: Milestone 3 -- verified with follow-ups, x")
            .unwrap();
        assert_eq!(&c[2], "verified with follow-ups");
        assert!(VERDICT_LINE
            .captures("- 2026-01-02: Milestone 3 -- changes needed")
            .is_some());
        assert!(VERDICT_LINE
            .captures("- 2026-01-02: Milestone 3 -- reopened: clause 1 failed")
            .is_none());
        assert!(VERDICT_LINE
            .captures("- 2026-01-02: Milestone 3 amended -- a follow-up of the verified verdict")
            .is_none());
        assert!(VERDICT_LINE
            .captures("- 2026-01-02: Milestone 3 -- verifiedly")
            .is_none());
    }

    #[test]
    fn maps_done_by_verdict_and_writes_only_its_own_row() {
        let plan = plan_migration(V3, RoadmapVersion::V3).unwrap();
        assert_eq!(plan.moves[0].new, "Verified");
        assert_eq!(plan.moves[1].new, "Not started");
        assert!(plan.text.contains("schema: roadmap/v4\n"));
        assert!(plan.text.contains("| Milestone 1: A | Verified | -- |\n"));
        assert!(plan.text.contains("| Milestone 12: L | Done | -- |\n"));
    }

    #[test]
    fn strips_controls() {
        assert_eq!(strip_controls("a\u{1b}[31mb\rc"), "a[31mbc");
    }

    #[test]
    fn feature_refs_become_milestone_refs() {
        assert_eq!(
            FEATURE_REF.replace_all(
                "**Dependencies:** Features 1, 2 and Feature 3",
                "Milestone${1} ${2}"
            ),
            "**Dependencies:** Milestones 1, 2 and Milestone 3"
        );
    }
}
