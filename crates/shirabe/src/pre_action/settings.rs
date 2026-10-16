//! The settings probe (PRD R12, DESIGN Decision 4): whether this host wires
//! the legacy entry point, `shirabe pr-body-hook`, into a settings file Claude
//! Code reads. When it does, the plugin's hook leaves the PR-body rules to it,
//! so each broken rule is reported once.
//!
//! The probe is strict on purpose: a line that only mentions the command, a
//! matcher that never fires on Bash, a redirected standard output, a file
//! that turns hooks off, or a `shirabe` the wired line couldn't find all read
//! as not wired. Every doubt, an unreadable or unparsable file included, gives
//! a duplicate report rather than a missing one. There is no fallback to the
//! input's `cwd`: a directory the agent chose is not where Claude Code reads
//! settings.

use std::ffi::OsStr;
use std::io::Read;
use std::path::Path;

use super::tokenize::tokenize;

/// The most a settings file may hold before it reads as not wired.
const MAX_SETTINGS_FILE: u64 = 4 * 1024 * 1024;

/// The probe on this process's environment: `HOME`, `CLAUDE_PROJECT_DIR` and
/// `PATH`, each ignored when unset or empty.
pub fn legacy_wired() -> bool {
    let var = |k: &str| std::env::var_os(k).filter(|v| !v.is_empty());
    let home = var("HOME");
    let project = var("CLAUDE_PROJECT_DIR");
    wired(
        home.as_deref().map(Path::new),
        project.as_deref().map(Path::new),
        var("PATH").as_deref(),
    )
}

/// Whether one of the settings files wires `shirabe pr-body-hook` and
/// `shirabe` resolves on `path`: `<home>/.claude/settings.json`, and with a
/// project directory its `.claude/settings.json` and
/// `.claude/settings.local.json`.
pub fn wired(home: Option<&Path>, project: Option<&Path>, path: Option<&OsStr>) -> bool {
    let mut files = Vec::new();
    if let Some(h) = home {
        files.push(h.join(".claude").join("settings.json"));
    }
    if let Some(p) = project {
        files.push(p.join(".claude").join("settings.json"));
        files.push(p.join(".claude").join("settings.local.json"));
    }
    files.iter().any(|f| file_wires(f)) && shirabe_on_path(path)
}

/// The wired command runs `shirabe` from `PATH` and exits 0 when `command -v
/// shirabe` fails, so a binary found only at `~/.shirabe/bin` means it does
/// nothing. A relative entry depends on the directory the hook runs in and
/// doesn't count.
fn shirabe_on_path(path: Option<&OsStr>) -> bool {
    use std::os::unix::fs::PermissionsExt;
    let Some(path) = path else { return false };
    std::env::split_paths(path)
        .filter(|dir| dir.is_absolute())
        .any(|dir| match std::fs::metadata(dir.join("shirabe")) {
            Ok(m) => m.is_file() && m.permissions().mode() & 0o111 != 0,
            Err(_) => false,
        })
}

fn file_wires(path: &Path) -> bool {
    let Some(text) = read_settings(path) else {
        return false;
    };
    let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) else {
        return false;
    };
    // Any value but `false` may turn hooks off.
    if v.get("disableAllHooks")
        .is_some_and(|d| d != &serde_json::Value::Bool(false))
    {
        return false;
    }
    let Some(entries) = v.pointer("/hooks/PreToolUse").and_then(|e| e.as_array()) else {
        return false;
    };
    entries.iter().any(|entry| {
        let fires_on_bash = match entry.get("matcher") {
            None => true,
            Some(m) => matches!(m.as_str(), Some("" | "*" | "Bash")),
        };
        fires_on_bash
            && entry
                .get("hooks")
                .and_then(|h| h.as_array())
                .is_some_and(|hooks| hooks.iter().any(hook_wires))
    })
}

/// A `"type": "command"` hook one of whose top-level segments is the bare
/// words `shirabe pr-body-hook`, alone or followed by `2>/dev/null`: niwa's
/// line. Any other redirection could throw the deny away.
fn hook_wires(hook: &serde_json::Value) -> bool {
    if hook.get("type").and_then(|t| t.as_str()) != Some("command") {
        return false;
    }
    let Some(command) = hook.get("command").and_then(|c| c.as_str()) else {
        return false;
    };
    let Ok(tok) = tokenize(command) else {
        return false;
    };
    tok.segments.iter().any(|seg| {
        let words: Vec<&str> = seg
            .words
            .iter()
            .map(|w| if w.bare { w.text.as_str() } else { "" })
            .collect();
        matches!(
            words.as_slice(),
            ["shirabe", "pr-body-hook"] | ["shirabe", "pr-body-hook", "2>/dev/null"]
        )
    })
}

/// A settings file's text, or `None` when it isn't a regular file, is larger
/// than the cap, or can't be read. A symlink is followed, as Claude Code
/// follows it; the `O_NONBLOCK` open and the `fstat` keep a FIFO or a device
/// swapped in from blocking the hook.
fn read_settings(path: &Path) -> Option<String> {
    use rustix::fs::{Mode, OFlags};
    let fd = rustix::fs::open(
        path,
        OFlags::RDONLY | OFlags::NONBLOCK | OFlags::CLOEXEC,
        Mode::empty(),
    )
    .ok()?;
    let file = std::fs::File::from(fd);
    let meta = file.metadata().ok()?;
    if !meta.is_file() || meta.len() > MAX_SETTINGS_FILE {
        return None;
    }
    let mut bytes = Vec::new();
    file.take(MAX_SETTINGS_FILE + 1)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.len() as u64 > MAX_SETTINGS_FILE {
        return None;
    }
    String::from_utf8(bytes).ok()
}

#[cfg(test)]
mod tests {
    use std::ffi::OsString;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;

    /// niwa's wiring line.
    const NIWA: &str =
        "command -v shirabe >/dev/null 2>&1 || exit 0; shirabe pr-body-hook 2>/dev/null || exit 0";

    /// A scratch directory holding a `home`, a `project` and a `bin` with an
    /// executable `shirabe` in it.
    struct Host {
        root: PathBuf,
    }

    impl Host {
        fn new() -> Self {
            static N: AtomicUsize = AtomicUsize::new(0);
            let root = std::env::temp_dir().join(format!(
                "shirabe-settings-{}-{}",
                std::process::id(),
                N.fetch_add(1, Ordering::SeqCst)
            ));
            let _ = std::fs::remove_dir_all(&root);
            for d in [
                "home/.claude",
                "project/.claude",
                "bin",
                "home/.shirabe/bin",
            ] {
                std::fs::create_dir_all(root.join(d)).unwrap();
            }
            for bin in ["bin/shirabe", "home/.shirabe/bin/shirabe"] {
                let p = root.join(bin);
                std::fs::write(&p, "#!/bin/sh\n").unwrap();
                use std::os::unix::fs::PermissionsExt;
                std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
            }
            Host { root }
        }

        fn home(&self) -> PathBuf {
            self.root.join("home")
        }

        fn project(&self) -> PathBuf {
            self.root.join("project")
        }

        fn path(&self) -> OsString {
            OsString::from(format!("/nonexistent:{}", self.root.join("bin").display()))
        }

        /// Write `json` at `rel` under the scratch root.
        fn write(&self, rel: &str, json: &str) {
            std::fs::write(self.root.join(rel), json).unwrap();
        }

        /// The probe with the project directory set.
        fn wired(&self) -> bool {
            wired(
                Some(&self.home()),
                Some(&self.project()),
                Some(&self.path()),
            )
        }
    }

    impl Drop for Host {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.root);
        }
    }

    fn settings(matcher: Option<&str>, command: &str) -> String {
        let mut entry = serde_json::json!({
            "hooks": [{ "type": "command", "command": command }]
        });
        if let Some(m) = matcher {
            entry["matcher"] = m.into();
        }
        serde_json::json!({ "hooks": { "PreToolUse": [entry] } }).to_string()
    }

    #[test]
    fn niwas_line_in_each_file_is_wiring() {
        for rel in [
            "home/.claude/settings.json",
            "project/.claude/settings.json",
            "project/.claude/settings.local.json",
        ] {
            let h = Host::new();
            assert!(!h.wired(), "no files");
            h.write(rel, &settings(Some("Bash"), NIWA));
            assert!(h.wired(), "{rel}");
        }
    }

    #[test]
    fn the_matchers_that_fire_on_bash() {
        for m in [None, Some(""), Some("*"), Some("Bash")] {
            let h = Host::new();
            h.write("home/.claude/settings.json", &settings(m, NIWA));
            assert!(h.wired(), "{m:?}");
        }
        for m in ["Edit", "Bash|Edit", "bash"] {
            let h = Host::new();
            h.write("home/.claude/settings.json", &settings(Some(m), NIWA));
            assert!(!h.wired(), "{m}");
        }
    }

    #[test]
    fn the_command_must_run_the_legacy_hook_with_stdout_intact() {
        for cmd in [
            "shirabe pr-body-hook",
            "shirabe pr-body-hook 2>/dev/null",
            "true && shirabe pr-body-hook",
        ] {
            let h = Host::new();
            h.write("home/.claude/settings.json", &settings(Some("Bash"), cmd));
            assert!(h.wired(), "{cmd}");
        }
        for cmd in [
            "echo shirabe pr-body-hook",
            "shirabe pr-body-hook >/dev/null",
            "shirabe pr-body-hook >/dev/null 2>&1",
            "shirabe pr-body-hook 2>&1 >/dev/null",
            "/usr/local/bin/shirabe pr-body-hook",
            "'shirabe' pr-body-hook",
            "shirabe pr-body-hook --x",
            "shirabe 'pr-body-hook",
            "x=\"$(shirabe pr-body-hook)\"",
        ] {
            let h = Host::new();
            h.write("home/.claude/settings.json", &settings(Some("Bash"), cmd));
            assert!(!h.wired(), "{cmd}");
        }
    }

    #[test]
    fn a_hook_that_isnt_a_command_hook_is_not_wiring() {
        let h = Host::new();
        let json = serde_json::json!({ "hooks": { "PreToolUse": [{
            "matcher": "Bash",
            "hooks": [{ "type": "prompt", "command": NIWA }]
        }]}});
        h.write("home/.claude/settings.json", &json.to_string());
        assert!(!h.wired());
    }

    #[test]
    fn a_file_that_turns_hooks_off_is_not_wiring() {
        let mut v: serde_json::Value = serde_json::from_str(&settings(None, NIWA)).unwrap();
        for (value, wires) in [
            (serde_json::json!(true), false),
            (serde_json::json!("yes"), false),
            (serde_json::json!(false), true),
        ] {
            let h = Host::new();
            v["disableAllHooks"] = value.clone();
            h.write("home/.claude/settings.json", &v.to_string());
            assert_eq!(h.wired(), wires, "{value}");
        }
    }

    #[test]
    fn an_unreadable_or_unparsable_file_is_not_wiring() {
        let h = Host::new();
        h.write("home/.claude/settings.json", "{ not json");
        assert!(!h.wired(), "unparsable");
        let h = Host::new();
        std::fs::create_dir(h.root.join("home/.claude/settings.json")).unwrap();
        assert!(!h.wired(), "a directory");
        let h = Host::new();
        h.write("home/.claude/settings.json", "{\"hooks\": 3}");
        assert!(!h.wired(), "wrong shape");
        // One bad file doesn't hide a good one.
        h.write("project/.claude/settings.json", &settings(None, NIWA));
        assert!(h.wired());
    }

    #[test]
    fn a_fifo_settings_file_is_not_read() {
        let h = Host::new();
        let fifo = h.root.join("home/.claude/settings.json");
        let made = std::process::Command::new("mkfifo")
            .arg(&fifo)
            .status()
            .is_ok_and(|s| s.success());
        if !made {
            return;
        }
        assert!(!h.wired());
    }

    #[test]
    fn a_symlinked_settings_file_is_followed() {
        let h = Host::new();
        h.write("dotfile.json", &settings(Some("Bash"), NIWA));
        std::os::unix::fs::symlink(
            h.root.join("dotfile.json"),
            h.root.join("home/.claude/settings.json"),
        )
        .unwrap();
        assert!(h.wired());
    }

    #[test]
    fn without_a_project_dir_only_the_user_file_is_read() {
        let h = Host::new();
        h.write("project/.claude/settings.json", &settings(None, NIWA));
        assert!(h.wired());
        // With CLAUDE_PROJECT_DIR unset the project's file isn't read, even
        // when it is the directory the command runs in.
        assert!(!wired(Some(&h.home()), None, Some(&h.path())));
        h.write("home/.claude/settings.json", &settings(None, NIWA));
        assert!(wired(Some(&h.home()), None, Some(&h.path())));
    }

    #[test]
    fn shirabe_must_resolve_on_an_absolute_path_entry() {
        let h = Host::new();
        h.write("home/.claude/settings.json", &settings(None, NIWA));
        let home = h.home();
        let probe = |path: Option<&OsStr>| wired(Some(&home), None, path);
        assert!(probe(Some(&h.path())));
        assert!(!probe(None), "no PATH");
        // Only at ~/.shirabe/bin, which the plugin's script finds and the
        // wired line doesn't.
        assert!(!probe(Some(OsStr::new("/nonexistent:/usr/bin/nope"))));
        // A relative entry doesn't count, even one that leads to `shirabe`
        // from the directory the tests run in.
        let cwd = std::env::current_dir().unwrap();
        let up = "../".repeat(cwd.components().count());
        let bin = h.root.join("bin");
        let rel = PathBuf::from(up).join(bin.strip_prefix("/").unwrap());
        assert!(rel.join("shirabe").is_file(), "{}", rel.display());
        assert!(!probe(Some(rel.as_os_str())));
        // A `shirabe` that isn't executable, or is a directory, isn't found.
        std::fs::set_permissions(
            h.root.join("bin/shirabe"),
            std::os::unix::fs::PermissionsExt::from_mode(0o644),
        )
        .unwrap();
        assert!(!probe(Some(&h.path())), "not executable");
        std::fs::remove_file(h.root.join("bin/shirabe")).unwrap();
        std::fs::create_dir(h.root.join("bin/shirabe")).unwrap();
        assert!(!probe(Some(&h.path())), "a directory");
    }
}
