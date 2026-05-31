//! Build script for the `shirabe` binary.
//!
//! Two jobs:
//!
//! 1. Inject the binary's version string. Mirrors the Go build's
//!    `-ldflags "-X main.version=<value>"` pattern: the release pipeline
//!    sets `SHIRABE_VERSION` to the tag being built, and unversioned local
//!    builds fall back to the crate's `CARGO_PKG_VERSION`. `main.rs` reads
//!    the resolved value through `env!("SHIRABE_VERSION")`.
//!
//! 2. Verify the active toolchain matches the pin in `rust-toolchain.toml`
//!    (DESIGN Decision 6). The pin gives reproducible builds; this check
//!    surfaces drift between a developer's active `rustc` and the pinned
//!    channel as a build warning so a mismatch is noticed before it shifts
//!    a `Debug`/`format!` byte the parity fixture depends on. It warns
//!    rather than aborts: rustup normally honors the pin automatically, so
//!    a mismatch means a deliberately overridden toolchain, and failing the
//!    build there would be more disruptive than informative.

use std::env;
use std::process::Command;

fn main() {
    inject_version();
    verify_toolchain();
}

/// Resolve and embed the version string read by `env!("SHIRABE_VERSION")`.
fn inject_version() {
    // Re-run if the override changes so the embedded string stays current.
    println!("cargo:rerun-if-env-changed=SHIRABE_VERSION");

    let version = env::var("SHIRABE_VERSION")
        .unwrap_or_else(|_| env::var("CARGO_PKG_VERSION").unwrap_or_default());

    println!("cargo:rustc-env=SHIRABE_VERSION={}", version);
}

/// Warn if the active `rustc` version differs from the channel pinned in
/// `rust-toolchain.toml` at the workspace root.
fn verify_toolchain() {
    // The build script's CWD is this crate's manifest dir; the workspace
    // root (where rust-toolchain.toml lives) is two levels up.
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap_or_default();
    let toolchain_path = format!("{}/../../rust-toolchain.toml", manifest_dir);
    println!("cargo:rerun-if-changed={}", toolchain_path);

    let Ok(contents) = std::fs::read_to_string(&toolchain_path) else {
        // No pin file found -- nothing to verify against.
        return;
    };

    let Some(pinned) = parse_channel(&contents) else {
        return;
    };

    let Some(active) = active_rustc_version() else {
        return;
    };

    if active != pinned {
        println!(
            "cargo:warning=active rustc {} does not match rust-toolchain.toml pin {} \
             (DESIGN Decision 6); reproducible builds assume the pinned toolchain",
            active, pinned
        );
    }
}

/// Extract the `channel = "X"` value from a `rust-toolchain.toml` body
/// without pulling in a TOML parser dependency.
fn parse_channel(contents: &str) -> Option<String> {
    for line in contents.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("channel") {
            let rest = rest.trim_start().strip_prefix('=')?.trim();
            return Some(rest.trim_matches('"').to_string());
        }
    }
    None
}

/// Return the active `rustc` semantic version (e.g. `"1.95.0"`), or `None`
/// if `rustc` can't be invoked or its output can't be parsed.
fn active_rustc_version() -> Option<String> {
    let rustc = env::var("RUSTC").unwrap_or_else(|_| "rustc".to_string());
    let output = Command::new(rustc).arg("--version").output().ok()?;
    if !output.status.success() {
        return None;
    }
    // `rustc 1.95.0 (hash date)` -> `1.95.0`
    let text = String::from_utf8(output.stdout).ok()?;
    text.split_whitespace().nth(1).map(str::to_string)
}
