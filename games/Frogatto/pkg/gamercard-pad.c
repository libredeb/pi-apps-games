/*
 * GamerCard (Arduino Leonardo) input shim for Frogatto 1.3.1.
 *
 * Frogatto hardcodes joystick buttons as:
 *   button 0 = attack toggle (keyboard D)
 *   button 1 = jump
 *   button 2 = tongue
 *
 * The Leonardo pad exposes A=b0, B=b1, X=b3, Y=b4 (no b2), so tongue
 * never fires. Remap GetButton queries and turn Start/Select into Esc
 * (pause menu) via PollEvent.
 *
 * Desired layout:
 *   A (b0)      = tongue
 *   B (b1)      = jump
 *   X (b3)      = attack toggle
 *   Start (b11) = Esc (pause / resume)
 *   Select(b10) = Esc (same; handy as a second pause key)
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <dlfcn.h>
#include <string.h>
#include <SDL/SDL.h>

enum {
	PHYS_A = 0,
	PHYS_B = 1,
	PHYS_X = 3,
	PHYS_SELECT = 10,
	PHYS_START = 11,
};

static Uint8 (*real_JoystickGetButton)(SDL_Joystick *, int) = NULL;
static int (*real_PollEvent)(SDL_Event *) = NULL;

static void ensure_syms(void)
{
	if (!real_JoystickGetButton)
		real_JoystickGetButton = dlsym(RTLD_NEXT, "SDL_JoystickGetButton");
	if (!real_PollEvent)
		real_PollEvent = dlsym(RTLD_NEXT, "SDL_PollEvent");
}

/* Logical index Frogatto asks for -> physical Leonardo button. */
static int map_button(int logical)
{
	switch (logical) {
	case 0: return PHYS_X; /* ATTACK  <- X */
	case 1: return PHYS_B; /* JUMP    <- B */
	case 2: return PHYS_A; /* TONGUE  <- A */
	default: return logical;
	}
}

Uint8 SDL_JoystickGetButton(SDL_Joystick *joystick, int button)
{
	ensure_syms();
	if (!real_JoystickGetButton)
		return 0;
	return real_JoystickGetButton(joystick, map_button(button));
}

int SDL_PollEvent(SDL_Event *event)
{
	int r;

	ensure_syms();
	if (!real_PollEvent)
		return 0;

	r = real_PollEvent(event);
	if (r && event &&
	    (event->type == SDL_JOYBUTTONDOWN || event->type == SDL_JOYBUTTONUP)) {
		const Uint8 btn = event->jbutton.button;
		if (btn == PHYS_START || btn == PHYS_SELECT) {
			const Uint8 pressed =
			    (event->type == SDL_JOYBUTTONDOWN) ? SDL_PRESSED : SDL_RELEASED;
			memset(event, 0, sizeof(*event));
			event->type = (pressed == SDL_PRESSED) ? SDL_KEYDOWN : SDL_KEYUP;
			event->key.type = event->type;
			event->key.state = pressed;
			event->key.keysym.sym = SDLK_ESCAPE;
		}
	}
	return r;
}
