#!/usr/bin/env python3
"""Validate JSONL events (one object per stdin line) against a JSON Schema.

Usage: validate_events.py <schema.json>   # instances read from stdin
Exit 0 if all lines valid, 1 otherwise (errors printed to stderr).
"""
import json
import pathlib
import sys

import jsonschema


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_events.py <schema.json>", file=sys.stderr)
        return 2
    schema = json.loads(pathlib.Path(sys.argv[1]).read_text())
    validator = jsonschema.Draft202012Validator(schema)
    errors = 0
    for i, raw in enumerate(sys.stdin, 1):
        line = raw.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"line {i}: invalid JSON: {exc}", file=sys.stderr)
            errors += 1
            continue
        for err in validator.iter_errors(obj):
            print(f"line {i}: {err.message}", file=sys.stderr)
            errors += 1
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
