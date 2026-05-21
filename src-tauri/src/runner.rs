//! Run the WSL helper and stream its JSONL events.
use crate::events::{parse_line, HelperEvent};
use std::io::{BufRead, BufReader, Read};

/// Read JSONL from `reader`, parse each non-empty line, and call `sink` for
/// every valid `HelperEvent`. Non-event lines are ignored. Returns parsed count.
pub fn stream_events<R: Read>(
    reader: R,
    mut sink: impl FnMut(HelperEvent),
) -> std::io::Result<usize> {
    let buf = BufReader::new(reader);
    let mut n = 0;
    for line in buf.lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        if let Ok(ev) = parse_line(&line) {
            sink(ev);
            n += 1;
        }
    }
    Ok(n)
}

/// The inner command string passed to `bash -lc` inside the distro.
pub fn wsl_inner_command(helper_path: &str, subcommand: &str) -> String {
    format!("{helper_path} {subcommand}")
}

/// `wsl.exe` arguments for running `bash -lc '<inner>'`. A named `distro` is
/// targeted with `-d <distro>`; an **empty** distro (not yet selected) omits
/// the flag so WSL uses its default distro — `wsl.exe -d "" …` is an invalid
/// name that exits without emitting any events.
pub fn wsl_exec_args(distro: &str, inner: &str) -> Vec<String> {
    let mut args = Vec::new();
    if !distro.is_empty() {
        args.push("-d".to_string());
        args.push(distro.to_string());
    }
    args.push("bash".to_string());
    args.push("-lc".to_string());
    args.push(inner.to_string());
    args
}

/// Build the `wsl.exe -d <distro> bash -lc '<helper> <sub>'` command (Windows).
#[cfg(windows)]
pub fn wsl_helper_command(
    distro: &str,
    helper_path: &str,
    subcommand: &str,
) -> std::process::Command {
    let mut c = std::process::Command::new("wsl.exe");
    c.args(wsl_exec_args(
        distro,
        &wsl_inner_command(helper_path, subcommand),
    ));
    c.stdout(std::process::Stdio::piped());
    c
}

/// A bundled resource staged into the WSL launcher dir. `rel` is the path
/// relative to both the source (`<resource_dir>/helper/`) and the destination
/// (`~/.hermes/launcher/`); `executable` marks scripts needing the +x bit.
pub struct StagedFile {
    pub rel: &'static str,
    pub executable: bool,
}

/// The helper files copied into WSL before any step runs. `launcher-helper.sh`
/// resolves its own dir and calls `lib/emit.py` / `lib/upsert_env.py`, so the
/// layout under `~/.hermes/launcher/` must mirror `helper/`.
pub const STAGED_FILES: &[StagedFile] = &[
    StagedFile {
        rel: "launcher-helper.sh",
        executable: true,
    },
    StagedFile {
        rel: "lib/emit.py",
        executable: false,
    },
    StagedFile {
        rel: "lib/upsert_env.py",
        executable: false,
    },
];

/// Bash run inside the distro to write one staged file from stdin into
/// `~/.hermes/launcher/<rel>`, creating parent dirs first (and +x for scripts).
/// Copying via stdin keeps bytes identical (LF preserved) and sidesteps
/// Windows→WSL path translation.
///
/// Deliberately quote-free with no command substitution: nested double quotes
/// (`"$(dirname "…")"`) get mangled crossing the Rust `Command` → `wsl.exe` →
/// bash boundary, which made bash exit 2. `rel` is a fixed, space-free path so
/// it needs no quoting, and `mkdir -p ~/.hermes/launcher/lib` creates both the
/// launcher dir and its `lib/` subdir in one shot.
pub fn wsl_stage_inner_command(rel: &str, executable: bool) -> String {
    let mut cmd = format!("mkdir -p ~/.hermes/launcher/lib && cat > ~/.hermes/launcher/{rel}");
    if executable {
        cmd.push_str(&format!(" && chmod +x ~/.hermes/launcher/{rel}"));
    }
    cmd
}

/// Build `wsl.exe -d <distro> bash -lc '<stage cmd>'` with stdin piped so the
/// caller can stream the file's bytes in (Windows only).
#[cfg(windows)]
pub fn wsl_stage_command(distro: &str, rel: &str, executable: bool) -> std::process::Command {
    let mut c = std::process::Command::new("wsl.exe");
    c.args(wsl_exec_args(
        distro,
        &wsl_stage_inner_command(rel, executable),
    ));
    c.stdin(std::process::Stdio::piped());
    c
}

/// Copy every `STAGED_FILES` entry from `helper_res_dir` (the bundled
/// `<resource_dir>/helper`) into the distro's `~/.hermes/launcher/`. Run once
/// before invoking the helper so a clean WSL has the script + its lib (Windows
/// only; verified on Parallels).
#[cfg(windows)]
pub fn stage_helper(distro: &str, helper_res_dir: &std::path::Path) -> Result<(), String> {
    use std::io::Write;
    for f in STAGED_FILES {
        let src = helper_res_dir.join(f.rel);
        let bytes =
            std::fs::read(&src).map_err(|e| format!("read resource {}: {e}", src.display()))?;
        let mut child = wsl_stage_command(distro, f.rel, f.executable)
            .spawn()
            .map_err(|e| format!("spawn wsl stage {}: {e}", f.rel))?;
        child
            .stdin
            .take()
            .ok_or_else(|| format!("no stdin for staging {}", f.rel))?
            .write_all(&bytes)
            .map_err(|e| format!("write {} to wsl: {e}", f.rel))?;
        // ChildStdin dropped at the `;` above → EOF for `cat` before we wait.
        let status = child
            .wait()
            .map_err(|e| format!("wait staging {}: {e}", f.rel))?;
        if !status.success() {
            return Err(format!(
                "staging {} failed (exit {:?})",
                f.rel,
                status.code()
            ));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::events::{HelperEvent, Step};
    use std::io::Cursor;

    #[test]
    fn streams_and_parses_events_ignoring_noise() {
        let input = concat!(
            "{\"event\":\"step\",\"step\":\"detect\",\"progress\":0,\"msg\":\"x\"}\n",
            "some non-json log line\n",
            "\n",
            "{\"event\":\"done\",\"step\":\"detect\",\"ok\":true}\n",
        );
        let mut got = Vec::new();
        let n = stream_events(Cursor::new(input), |ev| got.push(ev)).unwrap();
        assert_eq!(n, 2);
        assert_eq!(
            got[0],
            HelperEvent::Step {
                step: Step::Detect,
                progress: 0,
                msg: "x".into()
            }
        );
        assert_eq!(
            got[1],
            HelperEvent::Done {
                step: Step::Detect,
                ok: true
            }
        );
    }

    #[test]
    fn builds_wsl_inner_command_string() {
        let cmd = wsl_inner_command("/home/u/launcher-helper.sh", "detect");
        assert_eq!(cmd, "/home/u/launcher-helper.sh detect");
    }

    #[test]
    fn wsl_exec_args_target_named_distro() {
        assert_eq!(
            wsl_exec_args("Ubuntu-24.04", "echo hi"),
            ["-d", "Ubuntu-24.04", "bash", "-lc", "echo hi"]
        );
    }

    #[test]
    fn wsl_exec_args_omit_distro_flag_when_empty() {
        // Empty distro = not yet selected → fall back to the WSL default distro
        // (passing `-d ""` is an invalid distro name and emits no events).
        assert_eq!(wsl_exec_args("", "echo hi"), ["bash", "-lc", "echo hi"]);
    }

    #[test]
    fn builds_stage_inner_command_for_script() {
        // Quote-free + no command substitution: nested double quotes get mangled
        // crossing the Rust Command -> wsl.exe -> bash boundary (bash exit 2).
        let cmd = wsl_stage_inner_command("launcher-helper.sh", true);
        assert_eq!(
            cmd,
            "mkdir -p ~/.hermes/launcher/lib \
             && cat > ~/.hermes/launcher/launcher-helper.sh \
             && chmod +x ~/.hermes/launcher/launcher-helper.sh"
        );
    }

    #[test]
    fn builds_stage_inner_command_without_exec_bit() {
        let cmd = wsl_stage_inner_command("lib/emit.py", false);
        assert_eq!(
            cmd,
            "mkdir -p ~/.hermes/launcher/lib && cat > ~/.hermes/launcher/lib/emit.py"
        );
    }

    #[test]
    fn staged_files_cover_helper_and_lib_with_only_script_executable() {
        let rels: Vec<&str> = STAGED_FILES.iter().map(|f| f.rel).collect();
        assert_eq!(
            rels,
            ["launcher-helper.sh", "lib/emit.py", "lib/upsert_env.py"]
        );
        for f in STAGED_FILES {
            assert_eq!(f.executable, f.rel.ends_with(".sh"), "rel={}", f.rel);
        }
    }
}
