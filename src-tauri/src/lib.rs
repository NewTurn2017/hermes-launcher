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

    /// Run a WSL helper subcommand, streaming each parsed HelperEvent to the
    /// frontend over a Tauri Channel. WSL is Windows-only; other platforms
    /// report an environment error so the command still compiles/runs.
    #[tauri::command]
    pub async fn run_step(
        app: tauri::AppHandle,
        subcommand: String,
        args: Vec<String>,
        on_event: tauri::ipc::Channel<crate::events::HelperEvent>,
    ) -> Result<(), String> {
        // install-hermes streams for minutes; the wsl.exe spawn + blocking
        // stdout read must run off the webview thread or the UI freezes
        // ("응답 없음"). spawn_blocking moves it to the blocking pool while the
        // command still awaits completion (so the invoke promise resolves only
        // after every event has streamed — the slack-verify flow relies on it).
        tauri::async_runtime::spawn_blocking(move || -> Result<(), String> {
            run_step_blocking(app, subcommand, args, on_event)
        })
        .await
        .map_err(|e| e.to_string())?
    }

    /// Blocking body of [`run_step`], run on the blocking thread pool.
    fn run_step_blocking(
        app: tauri::AppHandle,
        subcommand: String,
        args: Vec<String>,
        on_event: tauri::ipc::Channel<crate::events::HelperEvent>,
    ) -> Result<(), String> {
        #[cfg(windows)]
        {
            use crate::runner::{stage_helper, stream_events, wsl_helper_command};
            use tauri::Manager;
            let distro = WizardState::load(&crate::state::default_state_path())
                .wsl_distro
                .unwrap_or_default();

            // Copy the bundled helper script + lib into the distro's ext4
            // (~/.hermes/launcher/) before running it; a clean WSL has neither.
            let helper_res_dir = app
                .path()
                .resource_dir()
                .map_err(|e| e.to_string())?
                .join("helper");
            if let Err(detail) = stage_helper(&distro, &helper_res_dir) {
                let _ = on_event.send(crate::events::HelperEvent::Error {
                    step: crate::events::Step::Detect,
                    level: crate::events::Level::Environment,
                    detail: format!("helper staging failed: {detail}"),
                });
                return Err(detail);
            }

            let helper = "$HOME/.hermes/launcher/launcher-helper.sh";
            let full = args.iter().fold(subcommand, |acc, a| format!("{acc} {a}"));
            let channel = on_event.clone();
            let mut child = wsl_helper_command(&distro, helper, &full)
                .spawn()
                .map_err(|e| e.to_string())?;
            let stdout = child.stdout.take().ok_or("no stdout from helper")?;
            stream_events(stdout, move |ev| {
                let _ = channel.send(ev);
            })
            .map_err(|e| e.to_string())?;
            let _ = child.wait();
            Ok(())
        }
        #[cfg(not(windows))]
        {
            let _ = (args, &app);
            on_event
                .send(crate::events::HelperEvent::Error {
                    step: crate::events::Step::Detect,
                    level: crate::events::Level::Environment,
                    detail: format!("run_step('{subcommand}') requires Windows + WSL"),
                })
                .map_err(|e| e.to_string())?;
            Ok(())
        }
    }
}

#[cfg(feature = "app")]
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            commands::set_step,
            commands::save_secret,
            commands::run_step
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
