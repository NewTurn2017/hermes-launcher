//! Hermes Launcher Tauri backend. Logic lives in plain modules so it is
//! testable with `cargo test` (no webview / Tauri runtime needed).

pub mod events;
pub mod runner;
pub mod secrets;
pub mod state;
pub mod wsl;

/// Entry point. The real Tauri context + frontend are wired under the `app`
/// feature (Plan 4); a backend-only build is a no-op so `cargo test`/`build`
/// work on any platform without the frontend assets.
#[cfg(not(feature = "app"))]
pub fn run() {
    eprintln!(
        "hermes-launcher backend built without the `app` feature; \
         run with --features app once the frontend exists"
    );
}

#[cfg(feature = "app")]
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod scaffold_tests {
    #[test]
    fn crate_builds_and_tests_run() {
        assert_eq!(2 + 2, 4);
    }
}
