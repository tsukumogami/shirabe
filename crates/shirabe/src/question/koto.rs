//! The koto calls behind `shirabe question`.
//!
//! koto is found on `PATH` and held to shirabe's koto minimum before any other
//! call. A koto refusal is passed through with its code, field and the check
//! it names, never reworded into success. Every call is bounded by
//! `CALL_TIMEOUT`: one that runs past it is stopped and reported with
//! `TIMEOUT_CODE`.

use std::io::{ErrorKind, Read};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use serde_json::Value;

use super::Failure;

/// shirabe's koto minimum, as the binary holds it. Its one definition is
/// `FLOOR` in scripts/assert-koto-floor.sh; scripts/koto-minimum-consistency_test.sh
/// fails when this copy disagrees.
pub const KOTO_MINIMUM: &str = "0.42.0";

/// A version's MAJOR.MINOR.PATCH, and whether a pre-release suffix
/// (`-rc1`) follows it.
fn parse_version(s: &str) -> Option<([u64; 3], bool)> {
    let s = s.trim_start_matches('v');
    let (core, pre) = match s.find(['-', '+']) {
        Some(i) => (&s[..i], s.as_bytes()[i] == b'-'),
        None => (s, false),
    };
    let mut out = [0u64; 3];
    let mut parts = core.split('.');
    for slot in out.iter_mut() {
        let p = parts.next()?;
        if p.is_empty() || !p.bytes().all(|c| c.is_ascii_digit()) {
            return None;
        }
        *slot = p.parse().ok()?;
    }
    if parts.next().is_some() {
        return None;
    }
    Some((out, pre))
}

/// Whether `have` meets `need`. A pre-release of a version comes before the
/// version itself, so `0.42.0-rc1` does not meet a minimum of `0.42.0`.
fn meets(have: ([u64; 3], bool), need: [u64; 3]) -> bool {
    have.0 > need || (have.0 == need && !have.1)
}

/// Run `koto version` and refuse a missing koto or one below the minimum.
pub fn check_version() -> Result<(), Failure> {
    let out = match exec(&["version"]) {
        Ok(o) => o,
        Err(ExecError::NotFound) => {
            return Err(Failure::koto_missing(format!(
                "koto is missing: no `koto` on PATH; shirabe needs koto {KOTO_MINIMUM} or later"
            )))
        }
        Err(ExecError::TimedOut) => return Err(Failure::koto(&timed_out(&["version"]))),
        Err(ExecError::Spawn(e)) => {
            return Err(Failure::koto_missing(format!(
                "koto could not be run ({e}); shirabe needs koto {KOTO_MINIMUM} or later"
            )))
        }
    };
    let text = String::from_utf8_lossy(&out.stdout);
    let installed = text.split_whitespace().nth(1).unwrap_or("").to_string();
    let need = parse_version(KOTO_MINIMUM)
        .expect("KOTO_MINIMUM is MAJOR.MINOR.PATCH")
        .0;
    match parse_version(&installed) {
        Some(have) if out.ok && meets(have, need) => Ok(()),
        Some(_) => Err(Failure::koto_missing(format!(
            "koto {installed} is installed; shirabe question needs koto {KOTO_MINIMUM} or later"
        ))),
        None => Err(Failure::koto_missing(format!(
            "koto's version is unreadable ({:?}); shirabe question needs koto {KOTO_MINIMUM} or later",
            text.trim()
        ))),
    }
}

/// The longest any one koto call may take. koto's calls here are local reads
/// and small writes, so a call still running after this is blocked, most
/// likely on a store lock, and is stopped rather than waited on.
pub const CALL_TIMEOUT: Duration = Duration::from_secs(10);

/// koto's stdout and stderr past this are not read; no koto output these
/// commands use comes near it.
const MAX_OUTPUT: u64 = 8 * 1024 * 1024;

/// Why a koto call produced no output.
enum ExecError {
    NotFound,
    Spawn(std::io::Error),
    TimedOut,
}

struct Output {
    ok: bool,
    code: Option<i32>,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

fn drain<R: Read + Send + 'static>(r: R) -> mpsc::Receiver<Vec<u8>> {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = r.take(MAX_OUTPUT).read_to_end(&mut buf);
        let _ = tx.send(buf);
    });
    rx
}

/// Run koto with `args`, stopping it at `CALL_TIMEOUT`. The output is read
/// on threads, so a koto that fills a pipe never stalls the wait, and the
/// threads are never joined: a child koto left holding a pipe cannot keep the
/// call past its deadline.
fn exec(args: &[&str]) -> Result<Output, ExecError> {
    let mut child = Command::new("koto")
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| match e.kind() {
            ErrorKind::NotFound => ExecError::NotFound,
            _ => ExecError::Spawn(e),
        })?;
    let out = drain(child.stdout.take().expect("stdout is piped"));
    let err = drain(child.stderr.take().expect("stderr is piped"));
    let deadline = Instant::now() + CALL_TIMEOUT;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => {
                std::thread::sleep(Duration::from_millis(5));
            }
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(ExecError::TimedOut);
            }
            Err(e) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(ExecError::Spawn(e));
            }
        }
    };
    let left = deadline.saturating_duration_since(Instant::now());
    let stdout = out.recv_timeout(left).map_err(|_| ExecError::TimedOut)?;
    let left = deadline.saturating_duration_since(Instant::now());
    let stderr = err.recv_timeout(left).map_err(|_| ExecError::TimedOut)?;
    Ok(Output {
        ok: status.success(),
        code: status.code(),
        stdout,
        stderr,
    })
}

/// The command line a message names: `koto` and its arguments, with any
/// argument past the first few left out, since a subject can be long.
fn command_line(args: &[&str]) -> String {
    let shown: Vec<&str> = args.iter().take(4).copied().collect();
    let more = if args.len() > 4 { " ..." } else { "" };
    format!("koto {}{more}", shown.join(" "))
}

fn timed_out(args: &[&str]) -> Refused {
    Refused {
        code: TIMEOUT_CODE.into(),
        field: None,
        check: None,
        error: format!(
            "`{}` did not finish within {} seconds and was stopped (koto may be waiting on a store lock); nothing further was written",
            command_line(args),
            CALL_TIMEOUT.as_secs()
        ),
    }
}

/// The code a koto call that ran past `CALL_TIMEOUT` carries.
pub const TIMEOUT_CODE: &str = "koto_timeout";

fn not_run(args: &[&str], e: ExecError) -> Refused {
    match e {
        ExecError::TimedOut => timed_out(args),
        ExecError::NotFound => Refused {
            code: "koto_failed".into(),
            field: None,
            check: None,
            error: "koto could not be run: no `koto` on PATH".into(),
        },
        ExecError::Spawn(e) => Refused {
            code: "koto_failed".into(),
            field: None,
            check: None,
            error: format!("koto could not be run: {e}"),
        },
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

impl Refused {
    pub fn timed_out(&self) -> bool {
        self.code == TIMEOUT_CODE
    }
}

/// The check name in a `prompt_unverified` message: `fails the '<check>' check`.
fn check_of(error: &str) -> Option<String> {
    let start = error.find("fails the '")? + "fails the '".len();
    let rest = &error[start..];
    let end = rest.find('\'')?;
    Some(rest[..end].to_string())
}

/// koto's refusal from a call that exited non-zero.
fn refusal(args: &[&str], out: &Output) -> Refused {
    let parsed: Option<Value> = serde_json::from_slice(&out.stdout).ok();
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
            format!("{} exited {}", command_line(args), out.code.unwrap_or(-1))
        } else {
            e
        }
    });
    Refused {
        code: get("code").unwrap_or_else(|| "koto_failed".into()),
        field: get("field"),
        check: check_of(&error),
        error,
    }
}

/// Run koto with `args` and parse its stdout as JSON.
pub fn run(args: &[&str]) -> Result<Value, Refused> {
    let out = exec(args).map_err(|e| not_run(args, e))?;
    if !out.ok {
        return Err(refusal(args, &out));
    }
    serde_json::from_slice(&out.stdout).map_err(|_| Refused {
        code: "koto_output".into(),
        field: None,
        check: None,
        error: format!("{} printed something that is not JSON", command_line(args)),
    })
}

/// Run koto and return its stdout unchanged (for `content read`).
pub fn run_raw(args: &[&str]) -> Result<Vec<u8>, Refused> {
    let out = exec(args).map_err(|e| not_run(args, e))?;
    if out.ok {
        Ok(out.stdout)
    } else {
        Err(refusal(args, &out))
    }
}

pub struct History {
    pub raw: Value,
}

impl History {
    pub fn read(identity: &str) -> Result<History, Refused> {
        run(&["decisions", "history", "--", identity]).map(|raw| History { raw })
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
    let shown = run(&["decisions", "show", "--", raiser, id])?;
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
