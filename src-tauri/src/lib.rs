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

/// Thin Tauri command wrappers (compiled only with the `app` feature). The
/// logic they delegate to lives in `state`/`secrets` and is tested directly.
#[cfg(feature = "app")]
mod commands {
    use crate::secrets::{KeyringStore, SecretStore};
    use crate::state::{StepStatus, WizardState};

    /// Persist a wizard step status to the default state file.
    #[tauri::command]
    pub fn set_step(step: String, status: String) -> Result<(), String> {
        let parsed = match status.as_str() {
            "pending" => StepStatus::Pending,
            "ok" => StepStatus::Ok,
            "skipped" => StepStatus::Skipped,
            "failed" => StepStatus::Failed,
            other => return Err(format!("unknown status: {other}")),
        };
        let path = crate::state::default_state_path();
        let mut s = WizardState::load(&path);
        s.set_step(&step, parsed);
        s.save(&path).map_err(|e| e.to_string())
    }

    /// Store (Some) or clear (None) a Slack token in the OS keychain.
    #[tauri::command]
    pub fn save_secret(key: String, value: Option<String>) -> Result<(), String> {
        match value {
            Some(v) => KeyringStore.store(&key, &v),
            None => KeyringStore.delete(&key),
        }
    }
}

#[cfg(feature = "app")]
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            commands::set_step,
            commands::save_secret
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod scaffold_tests {
    use crate::state::{StepStatus, WizardState};

    #[test]
    fn crate_builds_and_tests_run() {
        assert_eq!(2 + 2, 4);
    }

    #[test]
    fn resume_targets_first_incomplete_step() {
        let mut s = WizardState::default();
        s.set_step("env", StepStatus::Ok);
        s.set_step("install", StepStatus::Ok);
        let order = ["env", "install", "codex", "slack", "done"];
        let next = order.iter().find(|st| !s.is_complete(st)).copied();
        assert_eq!(next, Some("codex"));
    }
}
