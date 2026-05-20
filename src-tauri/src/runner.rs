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

/// Build the `wsl.exe -d <distro> bash -lc '<helper> <sub>'` command (Windows).
#[cfg(windows)]
pub fn wsl_helper_command(
    distro: &str,
    helper_path: &str,
    subcommand: &str,
) -> std::process::Command {
    let mut c = std::process::Command::new("wsl.exe");
    c.args([
        "-d",
        distro,
        "bash",
        "-lc",
        &wsl_inner_command(helper_path, subcommand),
    ]);
    c.stdout(std::process::Stdio::piped());
    c
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
}
