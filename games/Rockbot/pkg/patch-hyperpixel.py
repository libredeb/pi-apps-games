#!/usr/bin/env python3
"""Hyperpixel 720x720 fill + GamerCard Leonardo defaults for Rockbot (SDL2)."""
import sys
from pathlib import Path

GAMERCARD_BUTTONS = """\
#else
            // Arduino Leonardo (GamerCard): A jump, B shoot, X dash, Y shield
            button_codes_copy[BTN_JUMP].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_JUMP].value = 0;
            button_codes_copy[BTN_ATTACK].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_ATTACK].value = 1;
            button_codes_copy[BTN_DASH].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_DASH].value = 3;
            button_codes_copy[BTN_SHIELD].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_SHIELD].value = 4;
            button_codes_copy[BTN_L].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_L].value = 5;
            button_codes_copy[BTN_R].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_R].value = 6;
            button_codes_copy[BTN_QUIT].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_QUIT].value = 10;
            button_codes_copy[BTN_START].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_START].value = 11;
#endif
"""

SDL2_VIDEO_OLD = """\
SDL_Surface *SDLL_SetVideoMode(int width, int height, int bpp, Uint32 flags)
{
	(void)bpp;
	(void)flags;

	int win_w = width;
	int win_h = height;
	Uint32 window_flags = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE;
#ifdef PSP
	psp_platform::adjust_window_size(width, height, &win_w, &win_h, &window_flags);
#endif
"""

SDL2_VIDEO_NEW = """\
SDL_Surface *SDLL_SetVideoMode(int width, int height, int bpp, Uint32 flags)
{
	(void)bpp;
	(void)flags;

	/* GAMERCARD: always fill the Hyperpixel 4.0 720x720 panel. */
	int win_w = 720;
	int win_h = 720;
	Uint32 window_flags = SDL_WINDOW_SHOWN | SDL_WINDOW_BORDERLESS | SDL_WINDOW_FULLSCREEN_DESKTOP;
#ifdef PSP
	psp_platform::adjust_window_size(width, height, &win_w, &win_h, &window_flags);
#endif
	SDL_SetHint(SDL_HINT_RENDER_DRIVER, "opengles2");
	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
	SDL_SetHint(SDL_HINT_VIDEO_MINIMIZE_ON_FOCUS_LOSS, "0");
	SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
"""

SDL2_AFTER_WINDOW_OLD = """\
	if (window == NULL) {
		printf("SDLL_SetVideoMode: SDL_CreateWindow failed: %s\\n", SDL_GetError());
		return NULL;
	}

	renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
"""

SDL2_AFTER_WINDOW_NEW = """\
	if (window == NULL) {
		printf("SDLL_SetVideoMode: SDL_CreateWindow failed: %s\\n", SDL_GetError());
		return NULL;
	}

	SDL_SetWindowSize(window, win_w, win_h);
	SDL_SetWindowFullscreen(window, SDL_WINDOW_FULLSCREEN_DESKTOP);
	SDL_ShowWindow(window);
	SDL_RaiseWindow(window);
	SDL_PumpEvents();
	SDL_Delay(50);
	SDL_PumpEvents();

	renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
"""

SDL2_INIT_OLD = """\
const char *SDLL_JoystickName(int device_index)
{
	return SDL_JoystickNameForIndex(device_index);
}

int SDLL_Init(Uint32 flags)
{
	return SDL_Init(flags);
}
"""

SDL2_INIT_NEW = """\
const char *SDLL_JoystickName(int device_index)
{
	return SDL_JoystickNameForIndex(device_index);
}

int SDLL_Init(Uint32 flags)
{
	const char *padmap = SDL_getenv("SDL_GAMECONTROLLERCONFIG");
	if (padmap && padmap[0]) {
		SDL_SetHint(SDL_HINT_GAMECONTROLLERCONFIG, padmap);
	}
	SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
	flags |= SDL_INIT_GAMECONTROLLER | SDL_INIT_JOYSTICK;
	return SDL_Init(flags);
}
"""

SDL2_FLIP_OLD = """\
	if (SDL_UpdateTexture(texture, NULL, screen->pixels, screen->pitch) != 0) {
		return -1;
	}
	// Copy RGB as-is; ignore per-pixel alpha (avoids empty frame if A was left 0).
	SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_NONE);
	SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
	SDL_RenderClear(renderer);
	SDL_RenderCopy(renderer, texture, NULL, NULL);
	SDL_RenderPresent(renderer);
"""

SDL2_FLIP_NEW = """\
	/* GAMERCARD: software-scale 320x240 -> 720x720, then present 1:1.
	   Mesa OpenGL on the Pi copies a small STREAMING texture at native
	   size when dstrect is NULL, so GPU stretch cannot be trusted. */
	const int dst_w = 720;
	const int dst_h = 720;
	if (present_surface == NULL || present_surface->w != dst_w || present_surface->h != dst_h) {
		if (present_surface != NULL) {
			SDL_FreeSurface(present_surface);
		}
		present_surface = SDL_CreateRGBSurfaceWithFormat(0, dst_w, dst_h, 32, SDL_PIXELFORMAT_ARGB8888);
		if (present_surface == NULL) {
			return -1;
		}
		SDL_SetSurfaceBlendMode(present_surface, SDL_BLENDMODE_NONE);
	}
	SDL_SetSurfaceBlendMode(screen, SDL_BLENDMODE_NONE);
	{
		SDL_Rect src;
		SDL_Rect dst;
		src.x = 0;
		src.y = 0;
		src.w = screen->w;
		src.h = screen->h;
		dst.x = 0;
		dst.y = 0;
		dst.w = dst_w;
		dst.h = dst_h;
		if (SDL_SoftStretch(screen, &src, present_surface, &dst) != 0) {
			return -1;
		}
	}
	if (SDL_UpdateTexture(texture, NULL, present_surface->pixels, present_surface->pitch) != 0) {
		return -1;
	}
	SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_NONE);
	SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
	SDL_RenderSetLogicalSize(renderer, 0, 0);
	SDL_RenderSetIntegerScale(renderer, SDL_FALSE);
	SDL_RenderSetViewport(renderer, NULL);
	SDL_RenderSetClipRect(renderer, NULL);
	SDL_RenderSetScale(renderer, 1.0f, 1.0f);
	SDL_RenderClear(renderer);
	{
		SDL_Rect dst;
		dst.x = 0;
		dst.y = 0;
		dst.w = dst_w;
		dst.h = dst_h;
		SDL_RenderCopy(renderer, texture, NULL, &dst);
	}
	SDL_RenderPresent(renderer);
"""

SDL2_GLOBALS_OLD = """\
#elif defined(SDL2)

SDL_Window *window = NULL;
SDL_Renderer *renderer = NULL;
SDL_Texture *texture = NULL;
"""

SDL2_GLOBALS_NEW = """\
#elif defined(SDL2)

SDL_Window *window = NULL;
SDL_Renderer *renderer = NULL;
SDL_Texture *texture = NULL;
static SDL_Surface *present_surface = NULL;
"""

SDL2_DESTROY_OLD = """\
	if (texture != NULL) {
		SDL_DestroyTexture(texture);
		texture = NULL;
	}
"""

SDL2_DESTROY_NEW = """\
	if (present_surface != NULL) {
		SDL_FreeSurface(present_surface);
		present_surface = NULL;
	}
	if (texture != NULL) {
		SDL_DestroyTexture(texture);
		texture = NULL;
	}
"""

SDL2_TEXTURE_OLD = """\
	printf("SDL version: %s window=%dx%d game=%dx%d\\n",
		SDLL_GetCompiledVersion(), win_w, win_h, width, height);

	texture = SDL_CreateTexture(renderer,
								SDL_PIXELFORMAT_ARGB8888,
								SDL_TEXTUREACCESS_STREAMING,
								width, height);
"""

SDL2_TEXTURE_NEW = """\
	printf("SDL version: %s window=%dx%d game=%dx%d\\n",
		SDLL_GetCompiledVersion(), win_w, win_h, width, height);

	/* GAMERCARD: present texture is 720x720; game backbuffer stays at width x height. */
	texture = SDL_CreateTexture(renderer,
								SDL_PIXELFORMAT_ARGB8888,
								SDL_TEXTUREACCESS_STREAMING,
								win_w, win_h);
"""

SDL2_RENDERER_FALLBACK_OLD = """\
	if (renderer == NULL) {
		renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
	}
	if (renderer == NULL) {
		printf("SDLL_SetVideoMode: SDL_CreateRenderer failed: %s\\n", SDL_GetError());
		return NULL;
	}
"""

SDL2_RENDERER_FALLBACK_NEW = """\
	if (renderer == NULL) {
		renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
	}
	if (renderer == NULL) {
		SDL_SetHint(SDL_HINT_RENDER_DRIVER, "opengl");
		renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
	}
	if (renderer == NULL) {
		SDL_SetHint(SDL_HINT_RENDER_DRIVER, "software");
		renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
	}
	if (renderer == NULL) {
		printf("SDLL_SetVideoMode: SDL_CreateRenderer failed: %s\\n", SDL_GetError());
		return NULL;
	}
"""

PC_BUTTONS_OLD = """\
#else
            button_codes_copy[BTN_ATTACK].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_ATTACK].value = 2;
            button_codes_copy[BTN_JUMP].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_JUMP].value = 1;
            button_codes_copy[BTN_DASH].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_DASH].value = 0;
            button_codes_copy[BTN_SHIELD].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_SHIELD].value = 3;
            button_codes_copy[BTN_L].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_L].value = 6;
            button_codes_copy[BTN_R].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_R].value = 7;
            button_codes_copy[BTN_QUIT].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_QUIT].value = 8;
            button_codes_copy[BTN_START].type = JOYSTICK_INPUT_TYPE_BUTTON;
            button_codes_copy[BTN_START].value = 9;
#endif
"""

CMAKE_UNIX_OLD = """\
elseif(UNIX)
    add_definitions(-DNES_RESOLUTION -DLINUX -DPC)
    pkg_check_modules(X11 REQUIRED x11)
    list(APPEND ROCKBOT_EXTRA_LIBS ${X11_LIBRARIES})
    list(APPEND ROCKBOT_EXTRA_LIBS dl)
"""

CMAKE_UNIX_NEW = """\
elseif(UNIX)
    add_definitions(-DNES_RESOLUTION -DLINUX -DPC)
    list(APPEND ROCKBOT_EXTRA_LIBS dl)
"""

USED_KEYBOARD_OLD = """\
        if (_used_keyboard == true) { // next commands are all joystick only
            if (must_check_input_cheat == true) {
                check_cheat_input();
            }
            return;
        }
"""

USED_KEYBOARD_NEW = """\
        if (_used_keyboard == true) { // keep polling; a key must not drop joystick/controller events
            continue;
        }
"""

JOY_DOWN_OLD = """\
            if (event.type == SDL_JOYBUTTONDOWN) {
                if (check_input_reset) {
                    held_button_count++;
                    held_button_timer = timer.getTimer();
                }
"""

JOY_DOWN_NEW = """\
            if (event.type == SDL_JOYBUTTONDOWN) {
                if (getenv("ROCKBOT_DEBUG_INPUT")) {
                    fprintf(stderr, "ROCKBOT_DEBUG_INPUT: JOYBUTTONDOWN button=%d\\n", (int)event.jbutton.button);
                    fflush(stderr);
                }
                if (check_input_reset) {
                    held_button_count++;
                    held_button_timer = timer.getTimer();
                }
"""

CONTROLLER_BLOCK = r'''
#ifdef SDL2
        if (event.type == SDL_CONTROLLERBUTTONDOWN || event.type == SDL_CONTROLLERBUTTONUP) {
            const int pressed = (event.type == SDL_CONTROLLERBUTTONDOWN) ? 1 : 0;
            if (getenv("ROCKBOT_DEBUG_INPUT") && pressed) {
                fprintf(stderr, "ROCKBOT_DEBUG_INPUT: CONTROLLERBUTTON %d\n", (int)event.cbutton.button);
                fflush(stderr);
            }
            switch (event.cbutton.button) {
            case SDL_CONTROLLER_BUTTON_A:
                p1_input[BTN_JUMP] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_B:
                p1_input[BTN_ATTACK] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_X:
                p1_input[BTN_DASH] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_Y:
                p1_input[BTN_SHIELD] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:
                p1_input[BTN_L] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER:
                p1_input[BTN_R] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_BACK:
                p1_input[BTN_QUIT] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_START:
            case SDL_CONTROLLER_BUTTON_GUIDE:
                p1_input[BTN_START] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_DPAD_UP:
                p1_input[BTN_UP] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
                p1_input[BTN_DOWN] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_DPAD_LEFT:
                p1_input[BTN_LEFT] = pressed;
                break;
            case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
                p1_input[BTN_RIGHT] = pressed;
                break;
            default:
                break;
            }
        }
#endif

'''

INIT_JOY_OLD = """\
    SDLL_JoystickEventState(SDL_ENABLE);
    joystick1 = SDLL_JoystickOpen(SharedData::get_instance()->game_config.selected_input_device);
"""

INIT_JOY_NEW = """\
    SDLL_JoystickEventState(SDL_ENABLE);
#ifdef SDL2
    SDL_GameControllerEventState(SDL_ENABLE);
    {
        int n = SDL_NumJoysticks();
        for (int i = 0; i < n; i++) {
            if (SDL_IsGameController(i)) {
                SDL_GameControllerOpen(i);
            }
        }
    }
#endif
    joystick1 = SDLL_JoystickOpen(SharedData::get_instance()->game_config.selected_input_device);
"""

SELECT_PLAYER_OLD = """\
        } else if (input.p1_input[BTN_START] == 1) {
            input.clean();
            draw_lib.update_screen();
            timer.delay(80);
            break;
"""

SELECT_PLAYER_NEW = """\
        } else if (input.p1_input[BTN_START] == 1 || input.p1_input[BTN_JUMP] == 1) {
            input.clean();
            draw_lib.update_screen();
            timer.delay(80);
            break;
"""

LOAD_CONFIG_OLD = """\
        if (config.volume_sfx == 0) {
            config.volume_sfx = 128;
        }

    }
"""

LOAD_CONFIG_NEW = """\
        if (config.volume_sfx == 0) {
            config.volume_sfx = 128;
        }
        /* GamerCard: keep pad map and fullscreen even if an old config.sav exists. */
        config.get_default_buttons(config.button_codes);
        config.video_fullscreen = true;
        config.input_type = INPUT_TYPE_DOUBLE;
        config.input_mode = INPUT_MODE_DOUBLE;

    }
"""


def must_replace(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"failed to patch {label}")
    return text.replace(old, new, 1)


def patch_sdl_layer(path: Path) -> None:
    text = path.read_text()
    if "GAMERCARD: software-scale 320x240" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(text, SDL2_GLOBALS_OLD, SDL2_GLOBALS_NEW, "SDL2 present_surface")
    text = must_replace(text, SDL2_VIDEO_OLD, SDL2_VIDEO_NEW, "SDL2 SetVideoMode")
    text = must_replace(text, SDL2_AFTER_WINDOW_OLD, SDL2_AFTER_WINDOW_NEW, "SDL2 SetWindowSize")
    text = must_replace(text, SDL2_DESTROY_OLD, SDL2_DESTROY_NEW, "SDL2 destroy present")
    text = must_replace(text, SDL2_RENDERER_FALLBACK_OLD, SDL2_RENDERER_FALLBACK_NEW, "SDL2 renderer fallback")
    text = must_replace(text, SDL2_TEXTURE_OLD, SDL2_TEXTURE_NEW, "SDL2 present texture")
    text = must_replace(text, SDL2_INIT_OLD, SDL2_INIT_NEW, "SDL2 SDLL_Init")
    text = must_replace(text, SDL2_FLIP_OLD, SDL2_FLIP_NEW, "SDL2 Flip fill")
    path.write_text(text)
    print(f"{path}: patched")


def patch_config(path: Path) -> None:
    text = path.read_text()
    if "Arduino Leonardo (GamerCard)" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(text, PC_BUTTONS_OLD, GAMERCARD_BUTTONS, "GamerCard buttons")
    text = must_replace(
        text,
        "            input_type = INPUT_TYPE_DOUBLE;\n#endif",
        "            input_type = INPUT_TYPE_DOUBLE;\n"
        "            input_mode = INPUT_MODE_DOUBLE;\n#endif",
        "input_mode",
    )
    text = must_replace(
        text,
        "            video_fullscreen = false;",
        "            video_fullscreen = true;",
        "video_fullscreen",
    )
    path.write_text(text)
    print(f"{path}: patched")


def patch_cmake(path: Path) -> None:
    text = path.read_text()
    if "pkg_check_modules(X11 REQUIRED x11)" not in text:
        print(f"{path}: already patched")
        return
    text = must_replace(text, CMAKE_UNIX_OLD, CMAKE_UNIX_NEW, "CMake X11")
    path.write_text(text)
    print(f"{path}: patched")


def patch_input(path: Path) -> None:
    text = path.read_text()
    if "ROCKBOT_DEBUG_INPUT: JOYBUTTONDOWN" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(text, INIT_JOY_OLD, INIT_JOY_NEW, "open GameController")
    text = must_replace(text, USED_KEYBOARD_OLD, USED_KEYBOARD_NEW, "keyboard continue")
    text = must_replace(text, JOY_DOWN_OLD, JOY_DOWN_NEW, "joy debug")
    text = must_replace(
        text,
        "        }\n\n\n        // check AXIS buttons //",
        "        }\n" + CONTROLLER_BLOCK + "        // check AXIS buttons //",
        "controller events",
    )
    path.write_text(text)
    print(f"{path}: patched")


def patch_select_player(path: Path) -> None:
    text = path.read_text()
    if "BTN_START] == 1 || input.p1_input[BTN_JUMP] == 1) {\n            input.clean();\n            draw_lib.update_screen();\n            timer.delay(80);" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(text, SELECT_PLAYER_OLD, SELECT_PLAYER_NEW, "select_player Start/A")
    path.write_text(text)
    print(f"{path}: patched")


def patch_load_config(path: Path) -> None:
    text = path.read_text()
    if "GamerCard: keep pad map and fullscreen" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(text, LOAD_CONFIG_OLD, LOAD_CONFIG_NEW, "load_config GamerCard")
    path.write_text(text)
    print(f"{path}: patched")


def patch_readonly_dat(path: Path) -> None:
    text = path.read_text()
    old = "std::ios::in | std::ios::binary | std::ios::app"
    new = "std::ios::in | std::ios::binary /* GAMERCARD: no ios::app (needs write on /usr/share) */"
    if "GAMERCARD: no ios::app" in text:
        print(f"{path}: already patched")
        return
    if old not in text:
        raise SystemExit(f"failed to patch {path} readonly dat")
    path.write_text(text.replace(old, new))
    print(f"{path}: patched readonly dat")


GRAPHICS_COLORKEY_OLD = """\
    SDL_Surface *res_surface = SDLL_DisplayFormat(spriteCopy);
    SDLL_FreeSurface(spriteCopy);
    if (res_surface == NULL) {
        std::cout << "ERROR::::SDLSurfaceFromFile - DisplayFormat failed for '" << clean_filename << "'\\n";
        fflush(stdout);
        return NULL;
    }
    SDLL_SetColorKey(res_surface, SDL_SRCCOLORKEY, SDLL_MapRGB(game_screen, COLORKEY_R, COLORKEY_G, COLORKEY_B));
"""

GRAPHICS_COLORKEY_NEW = """\
    SDL_Surface *res_surface = SDLL_DisplayFormat(spriteCopy);
    SDLL_FreeSurface(spriteCopy);
    if (res_surface == NULL) {
        std::cout << "ERROR::::SDLSurfaceFromFile - DisplayFormat failed for '" << clean_filename << "'\\n";
        fflush(stdout);
        return NULL;
    }
    /* GAMERCARD: SDL 1.2 used 16-bit video (VIDEO_MODE_COLORS 16), so
       chroma (72,126,124) quantized to COLORKEY (75,125,125). SDL2
       DisplayFormat is ARGB8888 and those pixels stay visible (teal
       box on death_animation.png, RockDroid1 palmtrees, etc.). */
    if (res_surface->pixels != NULL && res_surface->format != NULL
            && res_surface->format->BytesPerPixel == 4) {
        if (SDLL_LockSurface(res_surface) == 0) {
            Uint8 *base = static_cast<Uint8 *>(res_surface->pixels);
            const Uint32 exact = SDLL_MapRGB(res_surface, COLORKEY_R, COLORKEY_G, COLORKEY_B);
            for (int y = 0; y < res_surface->h; y++) {
                Uint32 *row = reinterpret_cast<Uint32 *>(base + y * res_surface->pitch);
                for (int x = 0; x < res_surface->w; x++) {
                    Uint8 r, g, b;
                    SDLL_GetRGB(row[x], res_surface, &r, &g, &b);
                    const int d = abs(static_cast<int>(r) - COLORKEY_R)
                        + abs(static_cast<int>(g) - COLORKEY_G)
                        + abs(static_cast<int>(b) - COLORKEY_B);
                    if (d > 0 && d <= 6) {
                        row[x] = exact;
                    }
                }
            }
            SDLL_UnlockSurface(res_surface);
        }
    }
    SDLL_SetColorKey(res_surface, SDL_SRCCOLORKEY, SDLL_MapRGB(game_screen, COLORKEY_R, COLORKEY_G, COLORKEY_B));
"""


def patch_colorkey_quantize(path: Path) -> None:
    text = path.read_text()
    if "GAMERCARD: SDL 1.2 used 16-bit video" in text:
        print(f"{path}: already patched colorkey")
        return
    text = must_replace(text, GRAPHICS_COLORKEY_OLD, GRAPHICS_COLORKEY_NEW, "near-colorkey snap")
    path.write_text(text)
    print(f"{path}: patched colorkey snap")


def patch_graphics_scale(path: Path) -> None:
    text = path.read_text()
    if "if (scale_int < 1) {\n        scale_int = 1;\n    }\n    if (scale_int != 1) {" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(
        text,
        "    if (scale_int != 1) {\n"
        "        //SDL_Surface *src, SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect\n"
        "        SDL_Rect origin_rect = {0, 0, RES_W, RES_H};\n",
        "    if (scale_int < 1) {\n"
        "        scale_int = 1;\n"
        "    }\n"
        "    if (scale_int != 1) {\n"
        "        //SDL_Surface *src, SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect\n"
        "        SDL_Rect origin_rect = {0, 0, RES_W, RES_H};\n",
        "scale_int clamp",
    )
    old_fs = (
        "        game_screen_scaled = SDLL_SetVideoMode(RES_W, RES_H, VIDEO_MODE_COLORS,"
        " SDL_HWSURFACE | SDL_DOUBLEBUF | SDL_FULLSCREEN);\n"
    )
    new_fs = (
        "        scale_int = 1;\n"
        "        game_screen_scaled = SDLL_SetVideoMode(RES_W, RES_H, VIDEO_MODE_COLORS,"
        " SDL_HWSURFACE | SDL_DOUBLEBUF | SDL_FULLSCREEN);\n"
    )
    if old_fs not in text:
        raise SystemExit("failed to patch fullscreen scale_int")
    text = text.replace(old_fs, new_fs)
    path.write_text(text)
    print(f"{path}: patched scale_int")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    patch_sdl_layer(root / "sdl_layer.cpp")
    patch_config(root / "file/v4/file_config_v4.h")
    patch_cmake(root / "CMakeLists.txt")
    patch_input(root / "inputlib.cpp")
    patch_select_player(root / "sceneslib.cpp")
    patch_load_config(root / "file/file_io.cpp")
    patch_readonly_dat(root / "file/file_io.cpp")
    patch_graphics_scale(root / "graphicslib.cpp")
    patch_colorkey_quantize(root / "graphicslib.cpp")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
