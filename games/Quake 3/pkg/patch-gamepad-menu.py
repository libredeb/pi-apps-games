#!/usr/bin/env python3
"""Map SDL gamepad keys to Q3 UI keyboard keys in ioquake3 cl_keys.c."""
import re
import sys
from pathlib import Path

HELPER = r"""
/*
===================
CL_GamepadMenuKey

The Q3 UI only handles arrows / enter / escape. Translate SDL gamepad
keys so menus work without a keyboard.
===================
*/
static int CL_GamepadMenuKey( int key )
{
	switch ( key ) {
	case K_PAD0_DPAD_UP:
	case K_PAD0_LEFTSTICK_UP:
		return K_UPARROW;
	case K_PAD0_DPAD_DOWN:
	case K_PAD0_LEFTSTICK_DOWN:
		return K_DOWNARROW;
	case K_PAD0_DPAD_LEFT:
	case K_PAD0_LEFTSTICK_LEFT:
		return K_LEFTARROW;
	case K_PAD0_DPAD_RIGHT:
	case K_PAD0_LEFTSTICK_RIGHT:
		return K_RIGHTARROW;
	case K_PAD0_A:
		return K_ENTER;
	case K_PAD0_B:
	case K_PAD0_BACK:
		return K_ESCAPE;
	default:
		return key;
	}
}

"""


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "code/client/cl_keys.c")
    text = path.read_text()
    if "CL_GamepadMenuKey" in text:
        print(f"{path}: already patched")
        return 0

    text, n = re.subn(
        r"\nvoid CL_KeyDownEvent\( int key, unsigned time \)",
        HELPER + "void CL_KeyDownEvent( int key, unsigned time )",
        text,
        count=1,
    )
    if n != 1:
        print("failed to insert CL_GamepadMenuKey", file=sys.stderr)
        return 1

    text, n = re.subn(
        r"if \( \( key < 128 \|\| key == K_MOUSE1 \) &&",
        "if ( ( key < 128 || key == K_MOUSE1 || key == K_PAD0_A || key == K_PAD0_B || key == K_PAD0_START ) &&",
        text,
        count=1,
    )
    if n != 1:
        print("failed to patch cinematic skip", file=sys.stderr)
        return 1

    text, n = re.subn(
        r"VM_Call\(\s*uivm,\s*UI_KEY_EVENT,\s*key,\s*qtrue\s*\);",
        "VM_Call( uivm, UI_KEY_EVENT, CL_GamepadMenuKey( key ), qtrue );",
        text,
    )
    if n < 1:
        print("failed to patch UI_KEY_EVENT down", file=sys.stderr)
        return 1

    text, n = re.subn(
        r"VM_Call\(\s*uivm,\s*UI_KEY_EVENT,\s*key,\s*qfalse\s*\);",
        "VM_Call( uivm, UI_KEY_EVENT, CL_GamepadMenuKey( key ), qfalse );",
        text,
    )
    if n < 1:
        print("failed to patch UI_KEY_EVENT up", file=sys.stderr)
        return 1

    path.write_text(text)
    print(f"{path}: gamepad menu mapping applied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
