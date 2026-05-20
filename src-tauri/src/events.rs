//! Rust side of the JSONL event contract (helper/events.schema.json).
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Step {
    Detect,
    InstallHermes,
    CodexLogin,
    SlackManifest,
    SlackVerify,
    WriteConfig,
    Verify,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Level {
    Recoverable,
    Environment,
    Fatal,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum HelperEvent {
    Step { step: Step, progress: u8, msg: String },
    Detect {
        internet: bool,
        python3: bool,
        wslview: bool,
        cmd_exe: bool,
        hermes_installed: bool,
        codex_installed: bool,
        codex_authed: bool,
    },
    CodexAuthed {
        #[serde(default)]
        email: Option<String>,
    },
    CodexError { detail: String },
    CodexAborted,
    CodexTimeout,
    SlackManifest { json: String },
    SlackVerified { workspace: String, bot: String },
    SlackError { detail: String },
    Done { step: Step, ok: bool },
    Error { step: Step, level: Level, detail: String },
}

/// Parse one JSONL line into a `HelperEvent`.
pub fn parse_line(line: &str) -> Result<HelperEvent, serde_json::Error> {
    serde_json::from_str(line)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_step_event() {
        let ev = parse_line(r#"{"event":"step","step":"install-hermes","progress":42,"msg":"cloning repo"}"#).unwrap();
        assert_eq!(ev, HelperEvent::Step { step: Step::InstallHermes, progress: 42, msg: "cloning repo".into() });
    }

    #[test]
    fn parses_detect_event() {
        let line = r#"{"event":"detect","internet":true,"python3":true,"wslview":false,"cmd_exe":true,"hermes_installed":false,"codex_installed":true,"codex_authed":false}"#;
        let ev = parse_line(line).unwrap();
        assert!(matches!(ev, HelperEvent::Detect { internet: true, cmd_exe: true, codex_installed: true, .. }));
    }

    #[test]
    fn parses_codex_variants() {
        assert_eq!(parse_line(r#"{"event":"codex_authed","email":"u@example.com"}"#).unwrap(),
                   HelperEvent::CodexAuthed { email: Some("u@example.com".into()) });
        assert_eq!(parse_line(r#"{"event":"codex_authed","email":null}"#).unwrap(),
                   HelperEvent::CodexAuthed { email: None });
        assert_eq!(parse_line(r#"{"event":"codex_aborted"}"#).unwrap(), HelperEvent::CodexAborted);
        assert_eq!(parse_line(r#"{"event":"codex_timeout"}"#).unwrap(), HelperEvent::CodexTimeout);
        assert_eq!(parse_line(r#"{"event":"codex_error","detail":"no subscription"}"#).unwrap(),
                   HelperEvent::CodexError { detail: "no subscription".into() });
    }

    #[test]
    fn parses_done_and_error() {
        assert_eq!(parse_line(r#"{"event":"done","step":"verify","ok":true}"#).unwrap(),
                   HelperEvent::Done { step: Step::Verify, ok: true });
        assert_eq!(parse_line(r#"{"event":"error","step":"install-hermes","level":"fatal","detail":"boom"}"#).unwrap(),
                   HelperEvent::Error { step: Step::InstallHermes, level: Level::Fatal, detail: "boom".into() });
    }

    #[test]
    fn round_trips_to_same_json() {
        let line = r#"{"event":"slack_verified","workspace":"Acme","bot":"hermes"}"#;
        let ev = parse_line(line).unwrap();
        assert_eq!(serde_json::to_string(&ev).unwrap(), line);
    }

    #[test]
    fn rejects_unknown_event() {
        assert!(parse_line(r#"{"event":"explode"}"#).is_err());
    }
}
