//! Finding the prompt pointer for `shirabe question answer`.
//!
//! The pointer names the harness session running the command, the id of a
//! question-tool call in its record and the position of the question in that
//! call. With no `--call`, the latest call whose question at some position
//! carries the question's `prompt_header` is taken. Only structured fields are
//! read, and nothing from the record is printed: koto then verifies the
//! pointer against the record itself.
//!
//! The record is looked for where koto reads it, under `.claude/projects/` in
//! the account's home as the system's user database gives it (not `HOME`).

use std::ffi::CStr;
use std::fs::File;
use std::io::{BufRead, BufReader, Read};
use std::path::PathBuf;

use serde_json::Value;

use crate::question_guard::QUESTION_TOOL;

/// The longest record line read (koto's own bound).
const MAX_LINE: u64 = 16 << 20;

/// The account's home directory from the user database.
pub fn account_home() -> Option<PathBuf> {
    // SAFETY: getpwuid_r writes into the buffers we own; the returned pointer
    // aliases `pwd`, which outlives the read.
    unsafe {
        let uid = libc::getuid();
        let mut pwd: libc::passwd = std::mem::zeroed();
        let mut buf = vec![0 as libc::c_char; 16 * 1024];
        let mut result: *mut libc::passwd = std::ptr::null_mut();
        let rc = libc::getpwuid_r(uid, &mut pwd, buf.as_mut_ptr(), buf.len(), &mut result);
        if rc != 0 || result.is_null() || pwd.pw_dir.is_null() {
            return None;
        }
        let dir = CStr::from_ptr(pwd.pw_dir).to_str().ok()?;
        if dir.is_empty() {
            return None;
        }
        Some(PathBuf::from(dir))
    }
}

/// The harness record of session `sid`: `<home>/.claude/projects/*/<sid>.jsonl`.
pub fn record_path(home: &std::path::Path, sid: &str) -> Option<PathBuf> {
    if sid.is_empty() || sid.contains('/') || sid.contains("..") {
        return None;
    }
    let projects = home.join(".claude").join("projects");
    let name = format!("{sid}.jsonl");
    let mut found: Vec<PathBuf> = std::fs::read_dir(&projects)
        .ok()?
        .filter_map(Result::ok)
        .map(|e| e.path().join(&name))
        .filter(|p| p.is_file())
        .collect();
    found.sort();
    found.pop()
}

/// The latest question-tool call in the record whose question at some
/// position has `header`: `(call id, 1-based position)`.
pub fn find_call(path: &std::path::Path, header: &str) -> Option<(String, usize)> {
    let file = File::open(path).ok()?;
    let mut reader = BufReader::new(file);
    let mut latest: Option<(String, usize)> = None;
    let mut line = Vec::new();
    loop {
        line.clear();
        let n = (&mut reader)
            .take(MAX_LINE + 1)
            .read_until(b'\n', &mut line)
            .ok()?;
        if n == 0 {
            break;
        }
        if n as u64 > MAX_LINE {
            return None;
        }
        let Ok(entry) = serde_json::from_slice::<Value>(&line) else {
            continue;
        };
        if entry.get("type").and_then(Value::as_str) != Some("assistant") {
            continue;
        }
        let Some(parts) = entry.pointer("/message/content").and_then(Value::as_array) else {
            continue;
        };
        for part in parts {
            if part.get("type").and_then(Value::as_str) != Some("tool_use")
                || part.get("name").and_then(Value::as_str) != Some(QUESTION_TOOL)
            {
                continue;
            }
            let Some(id) = part.get("id").and_then(Value::as_str) else {
                continue;
            };
            let Some(qs) = part.pointer("/input/questions").and_then(Value::as_array) else {
                continue;
            };
            if let Some(pos) = qs
                .iter()
                .position(|q| q.get("header").and_then(Value::as_str) == Some(header))
            {
                latest = Some((id.to_string(), pos + 1));
            }
        }
    }
    latest
}
