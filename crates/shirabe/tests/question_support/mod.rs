//! Shared set-up for the `shirabe question` tests: a scratch directory with
//! the koto stand-in first on `PATH`, and helpers to read its call log and
//! serve its records.
#![allow(dead_code)]

use std::path::{Path, PathBuf};

use assert_cmd::Command;
use serde_json::Value;
use sha2::{Digest, Sha256};

pub fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/question")
        .join(name)
}

pub struct Standin {
    pub root: PathBuf,
    pub data: PathBuf,
    bin: PathBuf,
}

impl Standin {
    pub fn new() -> Standin {
        let mut rnd = [0u8; 8];
        getrandom::getrandom(&mut rnd).unwrap();
        let hex: String = rnd.iter().map(|b| format!("{b:02x}")).collect();
        let root = std::env::temp_dir().join(format!("shirabe-question-test-{hex}"));
        let data = root.join("koto");
        let bin = root.join("bin");
        std::fs::create_dir_all(&data).unwrap();
        std::fs::create_dir_all(&bin).unwrap();
        std::os::unix::fs::symlink(fixture("koto-standin.sh"), bin.join("koto")).unwrap();
        Standin { root, data, bin }
    }

    /// `shirabe question <args>` with the stand-in first on PATH and the
    /// run-mode and harness variables cleared.
    pub fn cmd(&self, args: &[&str]) -> Command {
        let mut c = Command::cargo_bin("shirabe").expect("binary `shirabe` builds");
        let path = format!(
            "{}:{}",
            self.bin.display(),
            std::env::var("PATH").unwrap_or_default()
        );
        c.env("PATH", path)
            .env("KOTO_STANDIN", &self.data)
            .env_remove("KOTO_RUN_MODE")
            .env_remove("CLAUDE_CODE_SESSION_ATTENDED")
            .env_remove("CLAUDE_CONFIG_DIR")
            .env_remove("CLAUDE_CODE_SESSION_ID")
            .arg("question")
            .args(args);
        c
    }

    /// A `PATH` holding no koto at all.
    pub fn cmd_without_koto(&self, args: &[&str]) -> Command {
        let empty = self.root.join("empty-bin");
        std::fs::create_dir_all(&empty).unwrap();
        let mut c = Command::cargo_bin("shirabe").unwrap();
        c.env("PATH", &empty)
            .env_remove("KOTO_RUN_MODE")
            .env_remove("CLAUDE_CODE_SESSION_ATTENDED")
            .env_remove("CLAUDE_CONFIG_DIR")
            .arg("question")
            .args(args);
        c
    }

    pub fn write(&self, rel: &str, bytes: impl AsRef<[u8]>) {
        let p = self.data.join(rel);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, bytes).unwrap();
    }

    pub fn file(&self, name: &str, bytes: impl AsRef<[u8]>) -> String {
        let p = self.root.join(name);
        std::fs::write(&p, bytes).unwrap();
        p.to_string_lossy().into_owned()
    }

    pub fn log(&self) -> Vec<String> {
        std::fs::read_to_string(self.data.join("log"))
            .unwrap_or_default()
            .lines()
            .map(str::to_string)
            .collect()
    }

    /// Every koto call exactly as shirabe gave it, before the stand-in
    /// reorders it.
    pub fn rawlog(&self) -> Vec<String> {
        std::fs::read_to_string(self.data.join("rawlog"))
            .unwrap_or_default()
            .lines()
            .map(str::to_string)
            .collect()
    }

    /// Calls other than reads: what would change koto's store.
    pub fn writes(&self) -> Vec<String> {
        self.log()
            .into_iter()
            .filter(|l| {
                l.starts_with("decisions record")
                    || l.starts_with("decisions content write")
                    || l.starts_with("decisions answer")
                    || l.starts_with("decisions readdress")
                    || l.starts_with("next")
            })
            .collect()
    }

    /// Serve a stored question: its history (raiser, id, packet) and content.
    pub fn serve(&self, session: &str, id: &str, stored: &[u8], extra_history: &str) -> String {
        let identity = format!("sid-{session}/{id}");
        let key = identity.replace('/', "_");
        self.write(&format!("content/{key}"), stored);
        self.write(
            &format!("history/{key}"),
            format!(
                "{{\"v\":1,\"identity\":\"{identity}\",\"raiser\":{{\"name\":\"{session}\",\"id\":\"sid-{session}\"}},\"question\":{{\"id\":\"{id}\",\"packet\":\"{}\",\"content_stored\":true}},\"open\":true,\"answer\":null,\"entries\":[]{extra_history}}}",
                packet(stored)
            ),
        );
        identity
    }
}

impl Drop for Standin {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

pub fn packet(bytes: &[u8]) -> String {
    let d = Sha256::digest(bytes);
    let hex: String = d.iter().map(|b| format!("{b:02x}")).collect();
    format!("sha256:{hex}")
}

pub fn header(identity: &str) -> String {
    let d = Sha256::digest(identity.as_bytes());
    let hex: String = d.iter().map(|b| format!("{b:02x}")).collect();
    format!("#{}", &hex[..11])
}

pub fn json(out: &[u8]) -> Value {
    serde_json::from_slice(out)
        .unwrap_or_else(|e| panic!("not JSON ({e}): {}", String::from_utf8_lossy(out)))
}

/// An undecided attempt `000000000001` in `session`, as `koto decisions
/// attempts` lists it.
pub fn undecided_attempt(s: &Standin, session: &str) {
    s.write(
        &format!("attempts/{session}"),
        format!("{{\"v\":1,\"in\":\"{session}\",\"attempts\":[{{\"id\":\"000000000001\",\"session\":\"{session}\",\"result\":\"undecided\",\"what\":\"cache store\"}},{{\"id\":\"000000000002\",\"session\":\"{session}\",\"result\":\"decided\",\"what\":\"queue\"}}],\"unreadable\":[]}}"),
    );
    // The stand-in numbers its records from the counter: keep the attempt ids
    // free.
    s.write("counter", "2");
}

/// The stored form `raise` writes for `v` (a decision question or a need),
/// from a raise against a fresh stand-in.
pub fn stored_of(v: &Value) -> Vec<u8> {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    let path = s.file("content.json", serde_json::to_vec(v).unwrap());
    let mut args = vec!["raise", "--in", "solo", "--content", path.as_str()];
    if v.get("options").is_some() {
        args.extend(["--attempt", "000000000001"]);
    }
    let out = s.cmd(&args).assert().success().get_output().clone();
    let key = json(&out.stdout)["identity"]
        .as_str()
        .unwrap()
        .replace('/', "_");
    std::fs::read(s.data.join("content").join(key)).unwrap()
}

/// good.json as a JSON value, for tests that change one part.
pub fn good() -> Value {
    serde_json::from_slice(&std::fs::read(fixture("good.json")).unwrap()).unwrap()
}
