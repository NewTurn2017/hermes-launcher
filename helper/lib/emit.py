#!/usr/bin/env python3
"""Build one compact JSON object from key=value / key:=rawjson args.

  key=value     -> string field
  key:=value    -> raw JSON field (number, bool, null, object, array)

Robust to string values that themselves contain ':=' (the raw form only
matches when an identifier is immediately followed by ':=').
"""
import json
import re
import sys

_RAW = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):=(.*)$", re.S)
_STR = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)


def main() -> int:
    ev = {}
    for arg in sys.argv[1:]:
        m = _RAW.match(arg)
        if m:
            ev[m.group(1)] = json.loads(m.group(2))
            continue
        m = _STR.match(arg)
        if not m:
            print(f"emit: bad arg: {arg}", file=sys.stderr)
            return 2
        ev[m.group(1)] = m.group(2)
    sys.stdout.write(json.dumps(ev, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
