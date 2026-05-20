//! Wizard state persisted to <localdata>/hermes-launcher/state.json.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StepStatus {
    Pending,
    Ok,
    Skipped,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WizardState {
    pub schema: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wsl_distro: Option<String>,
    pub steps: BTreeMap<String, StepStatus>,
}

impl Default for WizardState {
    fn default() -> Self {
        WizardState { schema: 1, wsl_distro: None, steps: BTreeMap::new() }
    }
}

impl WizardState {
    pub fn load(path: &Path) -> Self {
        std::fs::read_to_string(path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let json = serde_json::to_string_pretty(self).expect("serialize WizardState");
        std::fs::write(path, json)
    }

    pub fn set_step(&mut self, step: &str, status: StepStatus) {
        self.steps.insert(step.to_string(), status);
    }

    pub fn is_complete(&self, step: &str) -> bool {
        matches!(self.steps.get(step), Some(StepStatus::Ok) | Some(StepStatus::Skipped))
    }
}

/// `<localdata>/hermes-launcher/state.json` — `%LOCALAPPDATA%` on Windows.
pub fn default_state_path() -> PathBuf {
    let base = dirs::data_local_dir().unwrap_or_else(|| PathBuf::from("."));
    base.join("hermes-launcher").join("state.json")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_to_schema_1_empty() {
        let s = WizardState::default();
        assert_eq!(s.schema, 1);
        assert!(s.steps.is_empty());
        assert!(s.wsl_distro.is_none());
    }

    #[test]
    fn save_then_load_round_trips() {
        let dir = std::env::temp_dir().join(format!("hl-state-{}", std::process::id()));
        let path = dir.join("state.json");
        let mut s = WizardState::default();
        s.wsl_distro = Some("Ubuntu-24.04".into());
        s.set_step("env", StepStatus::Ok);
        s.set_step("install", StepStatus::Ok);
        s.set_step("codex", StepStatus::Pending);
        s.save(&path).unwrap();

        let loaded = WizardState::load(&path);
        assert_eq!(loaded, s);
        assert!(loaded.is_complete("env"));
        assert!(!loaded.is_complete("codex"));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn load_missing_file_returns_default() {
        let s = WizardState::load(Path::new("/nonexistent/hl/state.json"));
        assert_eq!(s, WizardState::default());
    }

    #[test]
    fn skipped_counts_as_complete() {
        let mut s = WizardState::default();
        s.set_step("slack", StepStatus::Skipped);
        assert!(s.is_complete("slack"));
    }
}
