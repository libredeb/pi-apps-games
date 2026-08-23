#!/usr/bin/env python3
"""Fill menu art missing from the 1997 q2_test pak0.

Yamagi animates m_cursor0..m_cursor14 at 10 Hz. q2_test only ships
frames 0-3, so the selector vanishes for 11 of every 15 frames.
Retail items (multiplayer, options, banners) are also absent and
RDraw_PicScaled logs "Can't find pic" every frame.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path


NUM_CURSOR_FRAMES = 15
TRANSPARENT = 255


def read_pak(path: Path) -> dict[str, bytes]:
    data = path.read_bytes()
    ident, dirofs, dirlen = struct.unpack_from("<4sii", data, 0)
    if ident != b"PACK":
        raise SystemExit(f"not a Quake PAK: {path}")
    files = {}
    for i in range(dirlen // 64):
        entry = data[dirofs + i * 64 : dirofs + i * 64 + 64]
        name = entry[:56].split(b"\x00", 1)[0].decode("latin1")
        ofs, size = struct.unpack_from("<ii", entry, 56)
        files[name] = data[ofs : ofs + size]
    return files


def decode_pcx(data: bytes) -> tuple[int, int, list[list[int]], bytes]:
    xmin, ymin, xmax, ymax = struct.unpack_from("<HHHH", data, 4)
    width, height = xmax - xmin + 1, ymax - ymin + 1
    bpl = struct.unpack_from("<H", data, 66)[0]
    raw = data[128:]
    out = bytearray()
    i = 0
    total = height * bpl
    while len(out) < total:
        b = raw[i]
        i += 1
        if b >= 0xC0:
            run = b & 0x3F
            val = raw[i]
            i += 1
            out.extend([val] * run)
        else:
            out.append(b)
    img = [list(out[y * bpl : y * bpl + width]) for y in range(height)]
    return width, height, img, data[-768:]


def encode_pcx(img: list[list[int]], palette: bytes) -> bytes:
    height = len(img)
    width = len(img[0])
    header = bytearray(128)
    header[0] = 0x0A
    header[1] = 5
    header[2] = 1
    header[3] = 8
    struct.pack_into("<HHHH", header, 4, 0, 0, width - 1, height - 1)
    struct.pack_into("<HH", header, 12, width, height)
    header[65] = 1
    struct.pack_into("<H", header, 66, width)
    struct.pack_into("<H", header, 68, 1)
    payload = bytearray()
    for row in img:
        x = 0
        while x < width:
            val = row[x] & 0xFF
            run = 1
            while x + run < width and row[x + run] == val and run < 63:
                run += 1
            if run > 1 or val >= 0xC0:
                payload.append(0xC0 | run)
                payload.append(val)
            else:
                payload.append(val)
            x += run
    if len(palette) != 768:
        raise SystemExit("palette must be 768 bytes")
    return bytes(header) + bytes(payload) + b"\x0c" + palette


def blit_conchar(dst, con, ch: int, dx: int, dy: int, scale: int) -> None:
    ch &= 255
    col, row = ch & 15, ch >> 4
    sx, sy = col * 8, row * 8
    for y in range(8):
        for x in range(8):
            pix = con[sy + y][sx + x]
            if pix == TRANSPARENT:
                continue
            for oy in range(scale):
                for ox in range(scale):
                    dst[dy + y * scale + oy][dx + x * scale + ox] = pix


def render_text(
    con, palette: bytes, text: str, scale: int, pad_x: int, height: int, alt: bool = False
) -> bytes:
    glyph = 8 * scale
    width = pad_x * 2 + max(len(text), 1) * glyph
    img = [[TRANSPARENT] * width for _ in range(height)]
    y0 = max(0, (height - glyph) // 2)
    x = pad_x
    extra = 128 if alt else 0
    for ch in text:
        blit_conchar(img, con, ord(ch) | extra, x, y0, scale)
        x += glyph
    return encode_pcx(img, palette)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} pak0.pak out_pics_dir")
    pak_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    files = read_pak(pak_path)
    for i in range(4):
        key = f"pics/m_cursor{i}.pcx"
        if key not in files:
            raise SystemExit(f"missing {key} in {pak_path}")

    existing = {n.lower() for n in files}
    for i in range(NUM_CURSOR_FRAMES):
        if f"pics/m_cursor{i}.pcx" in existing:
            continue
        src = files[f"pics/m_cursor{i % 4}.pcx"]
        (out_dir / f"m_cursor{i}.pcx").write_bytes(src)

    _, _, con, pal = decode_pcx(files["pics/conchars.pcx"])

    banners = {
        "m_banner_game": "GAME",
        "m_banner_load_game": "LOAD GAME",
        "m_banner_save_game": "SAVE GAME",
        "m_banner_multiplayer": "MULTIPLAYER",
        "m_banner_options": "OPTIONS",
        "m_banner_join_server": "JOIN SERVER",
        "m_banner_addressbook": "ADDRESS BOOK",
        "m_banner_video": "VIDEO",
    }
    for name, label in banners.items():
        if f"pics/{name}.pcx" in existing:
            continue
        (out_dir / f"{name}.pcx").write_bytes(
            render_text(con, pal, label, scale=2, pad_x=8, height=24)
        )

    written = sorted(p.name for p in out_dir.glob("*.pcx"))
    print(f"wrote {len(written)} pics in {out_dir}")


if __name__ == "__main__":
    main()
