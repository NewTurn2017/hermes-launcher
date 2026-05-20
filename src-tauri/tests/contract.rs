//! Integration contract test: every HelperEvent variant Rust serializes must
//! validate against helper/events.schema.json, using Plan 1's python validator
//! (the single source of truth shared by bats and Rust).
use hermes_launcher_lib::events::{HelperEvent, Level, Step};
use std::io::Write;
use std::process::{Command, Stdio};

fn schema_path() -> String {
    format!("{}/../helper/events.schema.json", env!("CARGO_MANIFEST_DIR"))
}
fn validator_path() -> String {
    format!("{}/../helper/tests/lib/validate_events.py", env!("CARGO_MANIFEST_DIR"))
}

fn validate(lines: &str) -> bool {
    let mut child = Command::new("python3")
        .arg(validator_path())
        .arg(schema_path())
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn python3 validator");
    child.stdin.as_mut().unwrap().write_all(lines.as_bytes()).unwrap();
    child.wait().expect("wait validator").success()
}

#[test]
fn all_variants_serialize_to_schema_valid_json() {
    let events = vec![
        HelperEvent::Step { step: Step::Detect, progress: 0, msg: "x".into() },
        HelperEvent::Detect {
            internet: true,
            python3: true,
            wslview: false,
            cmd_exe: true,
            hermes_installed: false,
            codex_installed: true,
            codex_authed: false,
        },
        HelperEvent::CodexAuthed { email: Some("u@example.com".into()) },
        HelperEvent::CodexAuthed { email: None },
        HelperEvent::CodexError { detail: "no subscription".into() },
        HelperEvent::CodexAborted,
        HelperEvent::CodexTimeout,
        HelperEvent::SlackManifest { json: "{}".into() },
        HelperEvent::SlackVerified { workspace: "Acme".into(), bot: "hermes".into() },
        HelperEvent::SlackError { detail: "invalid_auth".into() },
        HelperEvent::Done { step: Step::WriteConfig, ok: true },
        HelperEvent::Error { step: Step::InstallHermes, level: Level::Fatal, detail: "boom".into() },
    ];
    let mut jsonl = String::new();
    for ev in &events {
        jsonl.push_str(&serde_json::to_string(ev).unwrap());
        jsonl.push('\n');
    }
    assert!(validate(&jsonl), "serialized events failed schema validation:\n{jsonl}");
}

#[test]
fn validator_rejects_bad_event() {
    assert!(!validate("{\"event\":\"explode\"}\n"));
}
