#!/usr/bin/env python3
"""Map the GamerCard Arduino Leonardo gamepad to DreamChess menu/board keys."""
import sys
from pathlib import Path

HELPER = r'''
static int controller_button_to_key(Uint8 button)
{
	switch (button) {
	case SDL_CONTROLLER_BUTTON_DPAD_UP:
		return GG_KEY_UP;
	case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
		return GG_KEY_DOWN;
	case SDL_CONTROLLER_BUTTON_DPAD_LEFT:
		return GG_KEY_LEFT;
	case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
		return GG_KEY_RIGHT;
	case SDL_CONTROLLER_BUTTON_A:
		return GG_KEY_ACTION;
	case SDL_CONTROLLER_BUTTON_B:
	case SDL_CONTROLLER_BUTTON_BACK:
	case SDL_CONTROLLER_BUTTON_START:
		return GG_KEY_ESCAPE;
	case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:
		return 'p';
	case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER:
		return 'n';
	case SDL_CONTROLLER_BUTTON_Y:
		return 'r';
	default:
		return 0;
	}
}

'''

CONVERT_CASES = r'''
	case SDL_CONTROLLERBUTTONDOWN: {
		int key = controller_button_to_key(event->cbutton.button);
		if (key) {
			gg_event.type = GG_EVENT_KEY;
			gg_event.key = key;
		}
	} break;

	case SDL_CONTROLLERDEVICEADDED:
		if (SDL_IsGameController(event->cdevice.which))
			SDL_GameControllerOpen(event->cdevice.which);
		break;

'''

SDL_INIT_OLD = "if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_NOPARACHUTE) < 0) {"
SDL_INIT_NEW = """\
	SDL_SetHint(SDL_HINT_GAMECONTROLLERCONFIG,
		"03000000412300003680000001010000,Arduino Leonardo,a:b0,b:b1,x:b3,y:b4,back:b10,start:b11,leftshoulder:b5,rightshoulder:b6,dpdown:+a1,dpleft:-a0,dpright:+a0,dpup:-a1,leftx:a0,lefty:a1,platform:Linux,");

	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_NOPARACHUTE) < 0) {"""

GLEW_OLD = """\
	err = glewInit();
	if (err != GLEW_OK) {
"""
GLEW_NEW = """\
	glewExperimental = GL_TRUE;
	err = glewInit();
	if (err != GLEW_OK) {
"""


def must_replace(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"failed to patch {label}")
    return text.replace(old, new, 1)


def patch_gamegui(path: Path) -> None:
    text = path.read_text()
    if "controller_button_to_key" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(
        text,
        "extern SDL_Window *sdl_window;\n\ngg_event_t convert_event(SDL_Event *event)",
        "extern SDL_Window *sdl_window;\n" + HELPER + "gg_event_t convert_event(SDL_Event *event)",
        "gamegui helper",
    )
    text = must_replace(
        text,
        "\t} break;\n\n\tcase SDL_MOUSEBUTTONDOWN:",
        "\t} break;\n" + CONVERT_CASES + "\tcase SDL_MOUSEBUTTONDOWN:",
        "controller events",
    )
    path.write_text(text)
    print(f"{path}: patched")


def patch_ui(path: Path) -> None:
    text = path.read_text()
    if "SDL_INIT_GAMECONTROLLER" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(text, SDL_INIT_OLD, SDL_INIT_NEW, "SDL_Init")
    text = must_replace(
        text,
        """\
	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_NOPARACHUTE) < 0) {
		DBG_ERROR("SDL initialization failed: %s", SDL_GetError());
		exit(1);
	}

	ch_datadir();
""",
        """\
	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_NOPARACHUTE) < 0) {
		DBG_ERROR("SDL initialization failed: %s", SDL_GetError());
		exit(1);
	}

	{
		int i, n = SDL_NumJoysticks();
		for (i = 0; i < n; i++) {
			if (SDL_IsGameController(i))
				SDL_GameControllerOpen(i);
		}
	}

	ch_datadir();
""",
        "open controllers",
    )
    text = must_replace(text, GLEW_OLD, GLEW_NEW, "glewExperimental")
    path.write_text(text)
    print(f"{path}: patched")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    patch_gamegui(root / "dreamchess/src/gui/gamegui_driver.c")
    patch_ui(root / "dreamchess/src/gui/ui_sdlgl.c")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
