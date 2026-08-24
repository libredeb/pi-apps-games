#!/usr/bin/env python3
"""Remove iCCP / sRGB / gAMA / cHRM chunks that trigger libpng warnings."""
import struct
import sys
from pathlib import Path

DROP = {b"iCCP", b"sRGB", b"gAMA", b"cHRM"}
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def strip_file(path: Path) -> bool:
    data = path.read_bytes()
    if not data.startswith(PNG_MAGIC):
        return False

    out = bytearray(PNG_MAGIC)
    pos = 8
    changed = False
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        end = pos + 12 + length
        if end > len(data):
            break
        chunk = data[pos:end]
        pos = end
        if ctype in DROP:
            changed = True
        else:
            out.extend(chunk)
        if ctype == b"IEND":
            break

    if changed:
        path.write_bytes(bytes(out))
    return changed


def main() -> int:
    roots = [Path(p) for p in sys.argv[1:]] or [Path(".")]
    count = 0
    for root in roots:
        files = [root] if root.is_file() else sorted(root.rglob("*.png"))
        for png in files:
            if strip_file(png):
                count += 1
                print(f"stripped ICC/sRGB: {png}")
    print(f"updated {count} PNG file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
