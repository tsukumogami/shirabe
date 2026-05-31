//! Injects the binary's version string at build time.
//!
//! Mirrors the Go build's `-ldflags "-X main.version=<value>"` pattern:
//! the release pipeline sets `SHIRABE_VERSION` to the tag being built, and
//! unversioned local builds fall back to the crate's `CARGO_PKG_VERSION`.
//! `main.rs` reads the resolved value through `env!("SHIRABE_VERSION")`.

use std::env;

fn main() {
    // Re-run if the override changes so the embedded string stays current.
    println!("cargo:rerun-if-env-changed=SHIRABE_VERSION");

    let version = env::var("SHIRABE_VERSION")
        .unwrap_or_else(|_| env::var("CARGO_PKG_VERSION").unwrap_or_default());

    println!("cargo:rustc-env=SHIRABE_VERSION={}", version);
}
