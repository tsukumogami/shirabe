//! The koto calls behind `shirabe question`.
//!
//! koto is found on `PATH` and held to shirabe's koto minimum before any other
//! call. A koto refusal is passed through with its code, field and the check
//! it names, never reworded into success.

use std::io::ErrorKind;
use std::process::{Command, Stdio};

use serde_json::Value;

use super::Failure;

/// shirabe's koto minimum, as the binary holds it. Its one definition is
/// `FLOOR` in scripts/assert-koto-floor.sh; scripts/koto-minimum-consistency_test.sh
/// fails when this copy disagrees.
pub const KOTO_MINIMUM: &str = "0.42.0";

fn parse_version(s: &str) -> Option<[u64; 3]> {
    let mut out = [0u64; 3];
    let mut parts = s.trim_start_matches('v').split('.');
    for slot in out.iter_mut() {
        let p = parts.next()?;
        let digits: String = p.chars().take_while(char::is_ascii_digit).collect();
        *slot = digits.parse().ok()?;
    }
    Some(out)
}

/// Run `koto version` and refuse a missing koto or one below the minimum.
pub fn check_version() -> Result<(), Failure> {
    let out = match Command::new("koto")
        .arg("version")
        .stdin(Stdio::null())
        .output()
    {
        Ok(o) => o,
        Err(e) if e.kind() == ErrorKind::NotFound => {
            return Err(Failure::koto_missing(format!(
                "koto is missing: no `koto` on PATH; shirabe needs koto {KOTO_MINIMUM} or later"
            )))
        }
        Err(e) => {
            return Err(Failure::koto_missing(format!(
                "koto could not be run ({e}); shirabe needs koto {KOTO_MINIMUM} or later"
            )))
        }
    };
    let text = String::from_utf8_lossy(&out.stdout);
    let installed = text.split_whitespace().nth(1).unwrap_or("").to_string();
    let need = parse_version(KOTO_MINIMUM).expect("KOTO_MINIMUM is MAJOR.MINOR.PATCH");
    match parse_version(&installed) {
        Some(have) if out.status.success() && have >= need => Ok(()),
        Some(_) => Err(Failure::koto_missing(format!(
            "koto {installed} is installed; shirabe question needs koto {KOTO_MINIMUM} or later"
        ))),
        None => Err(Failure::koto_missing(format!(
            "koto's version is unreadable ({:?}); shirabe question needs koto {KOTO_MINIMUM} or later",
            text.trim()
        ))),
    }
}

/// A koto refusal, as koto printed it.
#[derive(Debug, Clone)]
pub struct Refused {
    pub code: String,
    pub field: Option<String>,
    pub check: Option<String>,
    pub error: String,
}

/// The check name in a `prompt_unverified` message: `fails the '<check>' check`.
fn check_of(error: &str) -> Option<String> {
    let start = error.find("fails the '")? + "fails the '".len();
    let rest = &error[start..];
    let end = rest.find('\'')?;
    Some(rest[..end].to_string())
}

/// Run koto with `args` and parse its stdout as JSON.
pub fn run(args: &[&str]) -> Result<Value, Refused> {
    let out = Command::new("koto")
        .args(args)
        .stdin(Stdio::null())
        .output()
        .map_err(|e| Refused {
            code: "koto_failed".into(),
            field: None,
            check: None,
            error: format!("koto could not be run: {e}"),
        })?;
    let parsed: Option<Value> = serde_json::from_slice(&out.stdout).ok();
    if out.status.success() {
        return parsed.ok_or_else(|| Refused {
            code: "koto_output".into(),
            field: None,
            check: None,
            error: format!("koto {} printed something that is not JSON", args.join(" ")),
        });
    }
    let status = out.status.code().unwrap_or(-1);
    let get = |k: &str| {
        parsed
            .as_ref()
            .and_then(|v| v.get(k))
            .and_then(Value::as_str)
            .map(str::to_string)
    };
    let error = get("error").unwrap_or_else(|| {
        let e = String::from_utf8_lossy(&out.stderr).trim().to_string();
        if e.is_empty() {
            format!("koto {} exited {status}", args.first().unwrap_or(&""))
        } else {
            e
        }
    });
    Err(Refused {
        code: get("code").unwrap_or_else(|| "koto_failed".into()),
        field: get("field"),
        check: check_of(&error),
        error,
    })
}

/// Run koto and return its stdout unchanged (for `content read`).
pub fn run_raw(args: &[&str]) -> Result<Vec<u8>, Refused> {
    let out = Command::new("koto")
        .args(args)
        .stdin(Stdio::null())
        .output()
        .map_err(|e| Refused {
            code: "koto_failed".into(),
            field: None,
            check: None,
            error: format!("koto could not be run: {e}"),
        })?;
    if out.status.success() {
        return Ok(out.stdout);
    }
    let parsed: Option<Value> = serde_json::from_slice(&out.stdout).ok();
    let get = |k: &str| {
        parsed
            .as_ref()
            .and_then(|v| v.get(k))
            .and_then(Value::as_str)
            .map(str::to_string)
    };
    let error =
        get("error").unwrap_or_else(|| String::from_utf8_lossy(&out.stderr).trim().to_string());
    Err(Refused {
        code: get("code").unwrap_or_else(|| "koto_failed".into()),
        field: get("field"),
        check: check_of(&error),
        error,
    })
}

/// A question as `koto decisions history` reads it.
pub struct History {
    pub raw: Value,
}

impl History {
    pub fn read(identity: &str) -> Result<History, Refused> {
        run(&["decisions", "history", identity]).map(|raw| History { raw })
    }
    fn q(&self, key: &str) -> Option<&Value> {
        self.raw.get("question").and_then(|q| q.get(key))
    }
    pub fn raiser(&self) -> String {
        self.raw
            .pointer("/raiser/name")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string()
    }
    pub fn id(&self) -> String {
        self.q("id")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string()
    }
    pub fn packet(&self) -> Option<String> {
        self.q("packet").and_then(Value::as_str).map(str::to_string)
    }
    pub fn open(&self) -> bool {
        self.raw
            .get("open")
            .and_then(Value::as_bool)
            .unwrap_or(false)
    }
    pub fn answer(&self) -> Option<&Value> {
        self.raw.get("answer").filter(|a| !a.is_null())
    }
    pub fn entries(&self) -> &[Value] {
        self.raw
            .get("entries")
            .and_then(Value::as_array)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }
}

/// koto's `prompt_header` for a question, from `koto decisions show`.
pub fn prompt_header(raiser: &str, id: &str) -> Result<String, Refused> {
    let shown = run(&["decisions", "show", raiser, id])?;
    shown
        .get("prompt_header")
        .and_then(Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| Refused {
            code: "no_packet".into(),
            field: None,
            check: None,
            error: format!(
                "koto shows no prompt_header for {raiser}:{id}: the question carries no packet"
            ),
        })
}
