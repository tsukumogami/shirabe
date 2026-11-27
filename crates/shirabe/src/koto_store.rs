//! Reading a koto run's event log straight from koto's session store.
//!
//! The log is read through koto's own read-only session reader
//! (`koto-session-reader`), from the sessions directory koto's rule names:
//! `$KOTO_HOME/sessions`, or `~/.koto/sessions` when `KOTO_HOME` is unset,
//! which holds the directory `koto session dir <name>` prints. The reader
//! opens a log without following a link and without waiting on a FIFO,
//! refuses anything that isn't a regular file, and refuses a store whose
//! layout marker names a layout it doesn't read. Nothing here writes to the
//! store, takes a lock on it, or runs koto.
//!
//! This module is the one place shirabe reads koto's store through the
//! reader crate. A later reader of koto sessions belongs here too, so the
//! rest of the binary sees only the plain values it returns.

use std::path::Path;
use std::sync::mpsc;
use std::time::Duration;

use koto_session_reader::engine::types::{Event, EventPayload, StateFileHeader};
use koto_session_reader::session::state_file_name;
use koto_session_reader::session::validate::validate_session_id;
use koto_session_reader::source::{read_session_events, sessions_dir, LocalDirSource, SessionSource};

/// The largest log the hooks read. A log larger than this isn't read at all,
/// so a hook's read stays bounded in memory and in time.
pub const LOG_READ_CAP: u64 = 64 * 1024 * 1024;

/// What a run's event log says, as far as the compaction hooks need it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunLog {
    /// The header's `execution_dir`: the directory the run started in.
    /// `None` when the header records none, or it isn't UTF-8.
    pub execution_dir: Option<String>,
    /// Every event in the log, oldest first.
    pub events: Vec<RunEvent>,
}

/// One event of a run's log.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunEvent {
    /// The event's seq, from 1.
    pub seq: u64,
    /// The event's type, as the log names it (`transitioned`,
    /// `context_added`, ...).
    pub kind: String,
    /// Who wrote the key, for a `context_added` event that records it.
    pub writer: Option<String>,
    /// Where an `execution_anchor_rebound` event moved the run. `None` for
    /// every other event, and when the path isn't UTF-8.
    pub rebound_to: Option<String>,
}

/// The log of koto session `ks`, read from the sessions directory koto's own
/// rule names. `None` when the directory can't be named, the store's layout
/// isn't one the reader reads, the log is missing, a link, not a regular
/// file, over [`LOG_READ_CAP`] or malformed, `ks` isn't a session name, or
/// the read doesn't finish within `timeout`. A zero `timeout` reads nothing.
pub fn read_run_log(ks: &str, timeout: Duration) -> Option<RunLog> {
    if timeout.is_zero() {
        return None;
    }
    let dir = sessions_dir(None).ok()?;
    read_in(&dir, ks, timeout)
}

/// [`read_run_log`] in the sessions directory `sessions_dir`.
///
/// The read runs on its own thread and its result comes back over a channel.
/// A read still going at `timeout` is given up on and its thread left to
/// finish on its own; the hook process exits soon after.
fn read_in(sessions_dir: &Path, ks: &str, timeout: Duration) -> Option<RunLog> {
    if timeout.is_zero() || validate_session_id(ks).is_err() {
        return None;
    }
    let source = LocalDirSource::new(sessions_dir).ok()?;
    let path = source.session_dir(ks).join(state_file_name(ks));
    // Only the size is decided here; the reader refuses a link, a
    // non-regular file and a FIFO itself.
    let meta = std::fs::symlink_metadata(&path).ok()?;
    if meta.len() > LOG_READ_CAP {
        return None;
    }
    let ks = ks.to_string();
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let read = read_session_events(&source, &ks)
            .ok()
            .map(|(header, events)| run_log_of(header, events));
        let _ = tx.send(read);
    });
    rx.recv_timeout(timeout).ok().flatten()
}

fn run_log_of(header: StateFileHeader, events: Vec<Event>) -> RunLog {
    RunLog {
        execution_dir: header
            .execution_dir
            .and_then(|d| d.into_os_string().into_string().ok()),
        events: events.into_iter().map(run_event_of).collect(),
    }
}

fn run_event_of(event: Event) -> RunEvent {
    let (writer, rebound_to) = match event.payload {
        EventPayload::ContextAdded { writer, .. } => (writer, None),
        EventPayload::ExecutionAnchorRebound { to, .. } => {
            (None, to.into_os_string().into_string().ok())
        }
        _ => (None, None),
    };
    RunEvent {
        seq: event.seq,
        kind: event.event_type,
        writer,
        rebound_to,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Instant;

    const KS: &str = "probe-run";
    const WAIT: Duration = Duration::from_secs(5);

    /// A throwaway sessions directory holding session `KS`'s directory,
    /// removed when dropped.
    struct Store(PathBuf);

    impl Drop for Store {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    impl Store {
        fn new() -> Store {
            static N: AtomicUsize = AtomicUsize::new(0);
            let n = N.fetch_add(1, Ordering::SeqCst);
            let dir =
                std::env::temp_dir().join(format!("shirabe-koto-store-{}-{n}", std::process::id()));
            let _ = fs::remove_dir_all(&dir);
            fs::create_dir_all(dir.join(KS)).unwrap();
            Store(dir)
        }

        fn log_path(&self) -> PathBuf {
            self.0.join(KS).join(state_file_name(KS))
        }

        fn write_log(&self, body: &str) {
            self.write_log_bytes(body.as_bytes());
        }

        fn write_log_bytes(&self, body: &[u8]) {
            fs::write(self.log_path(), body).unwrap();
        }

        fn read(&self) -> Option<RunLog> {
            read_in(&self.0, KS, WAIT)
        }
    }

    fn event(seq: u64, ty: &str, payload: serde_json::Value) -> String {
        serde_json::json!({"seq": seq, "timestamp": "2026-06-01T10:00:01.000Z", "type": ty,
            "payload": payload})
        .to_string()
    }

    /// A log as koto writes one: a header, then an event of each kind the
    /// hooks look at, every payload one koto reads.
    fn good_log() -> String {
        let header = serde_json::json!({"schema_version": 1, "workflow": KS,
            "template_hash": "00", "created_at": "2026-06-01T10:00:00.000Z",
            "execution_dir": "/w/a"});
        let lines = [
            header.to_string(),
            event(
                1,
                "workflow_initialized",
                serde_json::json!({"template_path": "/t/template.json"}),
            ),
            event(
                2,
                "transitioned",
                serde_json::json!({"from": null, "to": "work", "condition_type": "auto"}),
            ),
            event(
                3,
                "context_added",
                serde_json::json!({"key": "k", "hash": "00", "size": 1, "writer": "sync"}),
            ),
            event(
                4,
                "execution_anchor_rebound",
                serde_json::json!({"from": "/w/a", "to": "/w/moved"}),
            ),
            event(
                5,
                "context_read",
                serde_json::json!({"key": "k", "reader": "cli", "state": "work",
                    "present": true}),
            ),
        ];
        lines.join("\n") + "\n"
    }

    #[test]
    fn a_readable_session_gives_its_header_dir_and_every_event() {
        let store = Store::new();
        store.write_log(&good_log());
        let log = store.read().expect("the log reads");
        assert_eq!(log.execution_dir.as_deref(), Some("/w/a"));
        let seqs: Vec<u64> = log.events.iter().map(|e| e.seq).collect();
        assert_eq!(seqs, [1, 2, 3, 4, 5]);
        let kinds: Vec<&str> = log.events.iter().map(|e| e.kind.as_str()).collect();
        assert_eq!(
            kinds,
            [
                "workflow_initialized",
                "transitioned",
                "context_added",
                "execution_anchor_rebound",
                "context_read",
            ]
        );
        assert_eq!(log.events[2].writer.as_deref(), Some("sync"));
        assert_eq!(log.events[3].rebound_to.as_deref(), Some("/w/moved"));
        for (i, e) in log.events.iter().enumerate() {
            assert_eq!(e.writer.is_some(), i == 2, "{e:?}");
            assert_eq!(e.rebound_to.is_some(), i == 3, "{e:?}");
        }
    }

    #[test]
    fn a_missing_session_reads_as_none() {
        let store = Store::new();
        assert_eq!(store.read(), None);
        assert_eq!(read_in(&store.0, "no-such-run", WAIT), None);
        assert_eq!(read_in(&store.0.join("absent"), KS, WAIT), None);
    }

    #[test]
    fn a_log_that_is_a_link_or_a_directory_reads_as_none() {
        let store = Store::new();
        let real = store.0.join("real.jsonl");
        fs::write(&real, good_log()).unwrap();
        std::os::unix::fs::symlink(&real, store.log_path()).unwrap();
        assert_eq!(store.read(), None);
        fs::remove_file(store.log_path()).unwrap();
        fs::create_dir(store.log_path()).unwrap();
        assert_eq!(store.read(), None);
    }

    #[test]
    fn a_fifo_at_the_log_path_reads_as_none_without_waiting() {
        use std::os::unix::ffi::OsStrExt;
        let store = Store::new();
        let path = std::ffi::CString::new(store.log_path().as_os_str().as_bytes()).unwrap();
        // SAFETY: mkfifo reads a NUL-terminated path we own for the call.
        let made = unsafe { libc::mkfifo(path.as_ptr(), 0o600) };
        assert_eq!(made, 0, "mkfifo failed");
        let t = Instant::now();
        assert_eq!(store.read(), None);
        assert!(t.elapsed() < WAIT, "took {:?}", t.elapsed());
    }

    #[test]
    fn a_malformed_or_oversized_log_reads_as_none() {
        let store = Store::new();
        store.write_log("not json\n");
        assert_eq!(store.read(), None);
        // A seq gap is malformed too.
        let gapped = good_log().replace(r#""seq":5"#, r#""seq":7"#);
        store.write_log(&gapped);
        assert_eq!(store.read(), None);
        // A good log padded with trailing blanks reads, until the padding
        // takes it one byte over the cap: then its size alone refuses it.
        let mut padded = good_log().into_bytes();
        padded.extend([b' '; 1000]);
        store.write_log_bytes(&padded);
        assert!(store.read().is_some());
        padded.resize(LOG_READ_CAP as usize + 1, b' ');
        store.write_log_bytes(&padded);
        assert_eq!(store.read(), None);
    }

    #[test]
    fn a_store_with_a_newer_layout_reads_as_none() {
        let store = Store::new();
        store.write_log(&good_log());
        fs::write(store.0.join(".koto-store-layout"), "2\n").unwrap();
        assert_eq!(store.read(), None);
        fs::write(store.0.join(".koto-store-layout"), "1\n").unwrap();
        assert!(store.read().is_some());
    }

    #[test]
    fn an_invalid_session_id_or_a_zero_timeout_reads_nothing() {
        let store = Store::new();
        store.write_log(&good_log());
        for bad in ["../x", "", "a/b", "1run"] {
            assert_eq!(read_in(&store.0, bad, WAIT), None, "{bad:?}");
        }
        assert_eq!(read_in(&store.0, KS, Duration::ZERO), None);
        assert_eq!(read_run_log(KS, Duration::ZERO), None);
    }

    #[test]
    fn the_sessions_directory_holds_what_koto_session_dir_prints() {
        use koto_session_reader::koto_root::resolve_koto_root;
        use koto_session_reader::source::{resolve_sessions_dir, BackendKind};
        let dir = |backend: Option<BackendKind>, base: Option<&str>, root: Option<PathBuf>| {
            resolve_sessions_dir(backend, base.map(str::to_string), root)
                .map(|d| d.dir().to_path_buf())
        };
        // KOTO_HOME is the root, and the sessions live under it.
        let root = resolve_koto_root(Some("/k".into()), Some("/h".into()), None);
        assert_eq!(root.as_deref(), Some(Path::new("/k")));
        let want = Some(PathBuf::from("/k/sessions"));
        assert_eq!(dir(None, None, root.clone()), want);
        assert_eq!(dir(Some(BackendKind::Local), None, root.clone()), want);
        // The cloud backend's mirror is under the root whatever the base says.
        assert_eq!(dir(Some(BackendKind::Cloud), Some("/base"), root), want);
        // With KOTO_HOME unset the root is ~/.koto.
        let home = resolve_koto_root(None, Some("/h".into()), None);
        assert_eq!(dir(None, None, home), Some(PathBuf::from("/h/.koto/sessions")));
    }
}
