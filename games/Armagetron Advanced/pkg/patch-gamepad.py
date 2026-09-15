#!/usr/bin/env python3
"""Map the GamerCard Arduino Leonardo gamepad to keyboard events.

Armagetron Advanced 0.2.9.3.0 is an SDL 1.2 game and never learned about
joysticks (SDL 1.2 has no SDL_GameController-style abstraction), so this
patches the single choke point all SDL events pass through --
su_GetSDLInput() in uInputQueue.cpp, used by gameplay AND every menu -- to
turn the gamepad's D-pad and a few buttons into the same key events a
keyboard would send. Once that's done, the game can't tell gamepad and
keyboard input apart, so no other file needs to change.
"""
import sys
from pathlib import Path

JOYSTICK_INIT_OLD = """\
#ifndef DEDICATED
            if (
#ifndef NOSOUND
#ifndef DEFAULT_SDL_AUDIODRIVER
                SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) < 0 &&
#endif
#endif
                SDL_Init(SDL_INIT_VIDEO) < 0 )            {
                tERR_ERROR("Couldn't initialize SDL: " << SDL_GetError());
            }
            SDLCleanup sdlCleanup; // call SDL_Quit later
"""
JOYSTICK_INIT_NEW = """\
#ifndef DEDICATED
            if (
#ifndef NOSOUND
#ifndef DEFAULT_SDL_AUDIODRIVER
                SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_JOYSTICK) < 0 &&
#endif
#endif
                SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK) < 0 )            {
                tERR_ERROR("Couldn't initialize SDL: " << SDL_GetError());
            }
            SDLCleanup sdlCleanup; // call SDL_Quit later

            // GamerCard: open the first gamepad so its button/axis events start
            // showing up in the SDL event queue (see uInputQueue.cpp for how
            // they're turned into regular key events from there on).
            if (SDL_NumJoysticks() > 0)
                SDL_JoystickOpen(0);
"""

TRANSLATE_HELPER = """\
#ifndef DEDICATED
// GamerCard: translate the Arduino Leonardo gamepad into key events.
// The D-pad is wired as two analog axes (0: left/right, 1: up/down), so
// D-pad presses look like axis motion crossing a threshold. Buttons are
// plain SDL_JOYBUTTONDOWN/UP events. Both get rewritten in place into the
// equivalent SDL_KEYDOWN/UP so every caller of su_GetSDLInput() (gameplay
// and every menu) handles the gamepad exactly like a keyboard.
static void su_TranslateJoystickEvent(SDL_Event &e)
{
    static Sint16 axisState[2] = {0, 0};
    static const Sint16 threshold = 16384;

    SDLKey key = SDLK_UNKNOWN;
    Uint8 keystate = SDL_RELEASED;

    switch (e.type)
    {
    case SDL_JOYAXISMOTION:
    {
        if (e.jaxis.axis > 1)
            return;

        Sint16 &prev = axisState[e.jaxis.axis];
        Sint16 value = e.jaxis.value;
        SDLKey negKey = (e.jaxis.axis == 0) ? SDLK_LEFT : SDLK_UP;
        SDLKey posKey = (e.jaxis.axis == 0) ? SDLK_RIGHT : SDLK_DOWN;

        if (value < -threshold && prev >= -threshold)
        {
            key = negKey; keystate = SDL_PRESSED;
        }
        else if (value > threshold && prev <= threshold)
        {
            key = posKey; keystate = SDL_PRESSED;
        }
        else if (value >= -threshold && prev < -threshold)
        {
            key = negKey; keystate = SDL_RELEASED;
        }
        else if (value <= threshold && prev > threshold)
        {
            key = posKey; keystate = SDL_RELEASED;
        }
        prev = value;
        break;
    }
    case SDL_JOYBUTTONDOWN:
    case SDL_JOYBUTTONUP:
        switch (e.jbutton.button)
        {
        case 0:  key = SDLK_RETURN; break; // A: confirm / chat
        case 1:  key = SDLK_ESCAPE; break; // B: back / in-game menu
        case 3:  key = SDLK_SPACE;  break; // X: brake
        case 11: key = SDLK_ESCAPE; break; // start: in-game menu
        default: return;
        }
        keystate = (e.type == SDL_JOYBUTTONDOWN) ? SDL_PRESSED : SDL_RELEASED;
        break;
    default:
        return;
    }

    if (key == SDLK_UNKNOWN)
    {
        e.type = SDL_NOEVENT; // no threshold crossed: nothing to report
        return;
    }

    memset(&e, 0, sizeof(e));
    e.type = e.key.type = (keystate == SDL_PRESSED) ? SDL_KEYDOWN : SDL_KEYUP;
    e.key.state = keystate;
    e.key.keysym.sym = key;
    e.key.keysym.unicode = key; // non-zero: survives the bogus-event filter below
}
#endif

"""

POLL_OLD = """\
        sr_UnlockSDL();
        input_get=false;
    }

    su_markerRequired |= ret;
"""
POLL_NEW = """\
        sr_UnlockSDL();
        input_get=false;
    }

#ifndef DEDICATED
    if ( ret )
        su_TranslateJoystickEvent( tEvent );
#endif

    su_markerRequired |= ret;
"""


def must_replace(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"failed to patch {label}")
    return text.replace(old, new, 1)


def patch_init(path: Path) -> None:
    text = path.read_text()
    if "SDL_INIT_JOYSTICK" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(text, JOYSTICK_INIT_OLD, JOYSTICK_INIT_NEW, "SDL joystick init")
    path.write_text(text)
    print(f"{path}: patched")


def patch_queue(path: Path) -> None:
    text = path.read_text()
    if "su_TranslateJoystickEvent" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(
        text,
        "bool su_GetSDLInput(SDL_Event &tEvent,REAL &time){",
        TRANSLATE_HELPER + "bool su_GetSDLInput(SDL_Event &tEvent,REAL &time){",
        "translate helper",
    )
    text = must_replace(text, POLL_OLD, POLL_NEW, "poll call site")
    path.write_text(text)
    print(f"{path}: patched")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    patch_init(root / "src/tron/gArmagetron.cpp")
    patch_queue(root / "src/ui/uInputQueue.cpp")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
