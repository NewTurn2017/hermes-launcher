#!/usr/bin/env python3
"""Idempotently upsert KEY=VALUE into a .env-style file, preserving other lines.

Usage: upsert_env.py <path> <KEY> <VALUE>
"""
import pathlib
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: upsert_env.py <path> <KEY> <VALUE>", file=sys.stderr)
        return 2
    path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
    p = pathlib.Path(path)
    lines = p.read_text().splitlines() if p.exists() else []
    out, found = [], False
    for line in lines:
        if line.startswith(key + "="):
            if not found:
                out.append(f"{key}={value}")
                found = True
            # drop duplicate KEY= lines
        else:
            out.append(line)
    if not found:
        out.append(f"{key}={value}")
    p.write_text("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
