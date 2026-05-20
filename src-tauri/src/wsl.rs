//! WSL distro discovery. Parsing/decoding are cross-platform & tested;
//! the actual `wsl.exe` call is Windows-only.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Distro {
    pub name: String,
    pub state: String,
    pub version: u8,
    pub default: bool,
}

/// Parse the UTF-8-decoded text of `wsl -l -v`.
pub fn parse_list_verbose(text: &str) -> Vec<Distro> {
    let mut out = Vec::new();
    for line in text.lines().skip(1) {
        let trimmed = line.trim_start();
        if trimmed.trim().is_empty() {
            continue;
        }
        let default = trimmed.starts_with('*');
        let cleaned = trimmed.trim_start_matches('*').trim();
        let cols: Vec<&str> = cleaned.split_whitespace().collect();
        if cols.len() < 3 {
            continue;
        }
        out.push(Distro {
            name: cols[0].to_string(),
            state: cols[1].to_string(),
            version: cols[2].parse::<u8>().unwrap_or(0),
            default,
        });
    }
    out
}

/// Decode `wsl.exe`'s UTF-16LE management output (`-l -v`, `--status`).
pub fn decode_wsl_output(bytes: &[u8]) -> String {
    let (text, _, _) = encoding_rs::UTF_16LE.decode(bytes);
    text.into_owned()
}

/// List installed distros by invoking `wsl.exe -l -v` (Windows only).
#[cfg(windows)]
pub fn list_distros() -> std::io::Result<Vec<Distro>> {
    let out = std::process::Command::new("wsl.exe")
        .args(["-l", "-v"])
        .output()?;
    Ok(parse_list_verbose(&decode_wsl_output(&out.stdout)))
}

#[cfg(test)]
mod tests {
    use super::*;

    // `wsl -l -v` decoded text (header + two distros, default marked '*').
    const SAMPLE: &str = "  NAME            STATE           VERSION\n\
                          * Ubuntu-24.04    Running         2\n\
                            Debian          Stopped         2\n";

    #[test]
    fn parses_distros_with_default_flag() {
        let d = parse_list_verbose(SAMPLE);
        assert_eq!(d.len(), 2);
        assert_eq!(d[0].name, "Ubuntu-24.04");
        assert_eq!(d[0].state, "Running");
        assert_eq!(d[0].version, 2);
        assert!(d[0].default);
        assert_eq!(d[1].name, "Debian");
        assert!(!d[1].default);
    }

    #[test]
    fn skips_blank_and_short_lines() {
        let d = parse_list_verbose("NAME STATE VERSION\n\n  *  \n");
        assert!(d.is_empty());
    }

    #[test]
    fn decodes_utf16le_management_output() {
        // "Ab" in UTF-16LE = 0x41 0x00 0x62 0x00
        let bytes = [0x41u8, 0x00, 0x62, 0x00];
        assert_eq!(decode_wsl_output(&bytes), "Ab");
    }
}
