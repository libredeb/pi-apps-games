#!/usr/bin/env python3
"""GamerCard: make the 3D view fill the full Hyperpixel 4.0 (720x720) panel.

Aleph One's classic HUD layout (Source_Files/RenderOther/screen.cpp,
Screen::view_rect()) forces the 3D viewport above the status bar to a fixed
2:1 (width:height) aspect ratio. That was designed for 4:3/16:9 displays,
where "view height (window_width/2) + HUD height (160px)" exactly equals
the window height, so nothing is left over. On our square 720x720 panel,
that math leaves 720 - 160 (HUD) - 360 (2:1 view) = 200px of unused black
space, split between a strip above the view and a strip between the view
and the HUD -- confirmed both in the source and in a screenshot from the
real hardware.

Since this package only ever targets the Hyperpixel 4.0 panel, this patch
removes the forced 2:1 ratio and instead uses all the space actually
available: full window width, and the full height left above the HUD. No
unused strips, no need to stretch anything after the fact.

Invoked from build.sh right after the upstream source tarball is
extracted, before ./configure && make.
"""
import sys
from pathlib import Path

OLD = """\
	else
	{
		int available_height = window_height() - hud_rect().h;
		if (window_width() > available_height * 2)
		{
			r.w = available_height * 2;
			r.h = available_height;
		}
		else
		{
			r.w = window_width();
			r.h = window_width() / 2;
		}
		r.x = (width() - r.w) / 2;
		r.y = (height() - window_height()) / 2 + (available_height - r.h) / 2;
	}
"""

NEW = """\
	else
	{
		// GamerCard: fill the whole Hyperpixel 4.0 panel instead of forcing
		// the classic 2:1 view aspect (see patch-fullscreen-view.py).
		int available_height = window_height() - hud_rect().h;
		r.w = window_width();
		r.h = available_height;
		r.x = (width() - r.w) / 2;
		r.y = (height() - window_height()) / 2;
	}
"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch-fullscreen-view.py <alephone-source-dir>", file=sys.stderr)
        return 1

    screen_cpp = Path(sys.argv[1]) / "Source_Files" / "RenderOther" / "screen.cpp"
    text = screen_cpp.read_text()

    if "fill the whole Hyperpixel 4.0 panel" in text:
        print(f"{screen_cpp}: already patched")
        return 0

    if OLD not in text:
        print(f"{screen_cpp}: expected view_rect() block not found, upstream source changed?", file=sys.stderr)
        return 1

    screen_cpp.write_text(text.replace(OLD, NEW, 1))
    print(f"{screen_cpp}: patched (full-height 3D view, no forced 2:1 aspect)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
