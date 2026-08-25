#!/usr/bin/env python3
"""Make DreamChess 0.3.0 work on Wayland/EGL (libwc) instead of GLX/GLEW."""
import sys
from pathlib import Path


def must_replace(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"failed to patch {label}")
    return text.replace(old, new, 1)


def patch_header(path: Path) -> None:
    text = path.read_text()
    if "<epoxy/gl.h>" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(text, "#include <GL/glew.h>", "#include <epoxy/gl.h>", "ui_sdlgl.h glew include")
    path.write_text(text)
    print(f"{path}: patched")


def patch_ui(path: Path) -> None:
    text = path.read_text()
    if "epoxy_has_gl_extension" in text:
        print(f"{path}: already patched")
        return

    text = must_replace(text, "#include <GL/glew.h>\n", "", "ui_sdlgl.c glew include")
    if "int i, err;" in text:
        text = must_replace(text, "	int i, err;\n", "	int i;\n", "unused err")

    text = must_replace(
        text,
        """\
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 1);

	sdl_window =
		SDL_CreateWindow("DreamChess", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, width, height, video_flags);
""",
        """\
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 1);
	SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);
	SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
	SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
	SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_COMPATIBILITY);

	sdl_window =
		SDL_CreateWindow("DreamChess", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, width, height, video_flags);
""",
        "GL attributes",
    )

    text = must_replace(
        text,
        """\
	if (!SDL_GL_CreateContext(sdl_window)) {
		DBG_ERROR("Failed to create GL context: %s", SDL_GetError());
		SDL_DestroyWindow(sdl_window);
		mode_set_failed = 1;
		return 1;
	}

	glewExperimental = GL_TRUE;
	err = glewInit();
	if (err != GLEW_OK) {
		DBG_ERROR("Failed to initialize GLEW: %s", glewGetErrorString(err));
		exit(1);
	}

	if (!glewIsSupported("GL_ARB_framebuffer_object")) {
		DBG_ERROR("OpenGL extension GL_ARB_framebuffer_object not supported");
		exit(1);
	}

	if (!glewIsSupported("GL_ARB_texture_non_power_of_two")) {
		DBG_ERROR("OpenGL extension GL_ARB_texture_non_power_of_two not supported");
		exit(1);
	}
""",
        """\
	if (!SDL_GL_CreateContext(sdl_window)) {
		DBG_ERROR("Failed to create GL 2.1 context (%s); retrying without profile", SDL_GetError());
		SDL_GL_ResetAttributes();
		SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
		SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 1);
		SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);
		if (!SDL_GL_CreateContext(sdl_window)) {
			DBG_ERROR("Failed to create GL context: %s", SDL_GetError());
			SDL_DestroyWindow(sdl_window);
			mode_set_failed = 1;
			return 1;
		}
	}

	DBG_LOG("SDL video driver: %s", SDL_GetCurrentVideoDriver());
	DBG_LOG("OpenGL: %s / %s", glGetString(GL_VENDOR), glGetString(GL_VERSION));
	{
		GLint max_tex = 0;
		glGetIntegerv(GL_MAX_TEXTURE_SIZE, &max_tex);
		DBG_LOG("OpenGL renderer: %s, max texture %d", glGetString(GL_RENDERER), max_tex);
	}

	if (!epoxy_has_gl_extension("GL_ARB_framebuffer_object") &&
		!epoxy_has_gl_extension("GL_EXT_framebuffer_object") && epoxy_gl_version() < 30) {
		DBG_ERROR("OpenGL framebuffer objects are not supported");
		exit(1);
	}

	if (!epoxy_has_gl_extension("GL_ARB_texture_non_power_of_two") && epoxy_gl_version() < 20) {
		DBG_ERROR("OpenGL non-power-of-two textures are not supported");
		exit(1);
	}
""",
        "GLEW -> epoxy",
    )

    path.write_text(text)
    print(f"{path}: patched")


def patch_cmake(path: Path) -> None:
    text = path.read_text()
    if "epoxy" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(
        text,
        "find_package(OpenGL REQUIRED)\nfind_package(GLEW REQUIRED)\nfind_package(EXPAT REQUIRED)\n",
        """find_package(OpenGL REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
find_package(EXPAT REQUIRED)
""",
        "cmake find epoxy",
    )
    text = must_replace(
        text,
        "    ${OPENGL_INCLUDE_DIR}\n    ${GLEW_INCLUDE_DIR}\n    ${EXPAT_INCLUDE_DIR}\n",
        "    ${OPENGL_INCLUDE_DIR}\n    ${EPOXY_INCLUDE_DIRS}\n    ${EXPAT_INCLUDE_DIR}\n",
        "cmake includes",
    )
    text = must_replace(
        text,
        "    GLEW::GLEW\n",
        "    PkgConfig::EPOXY\n",
        "cmake link epoxy",
    )
    path.write_text(text)
    print(f"{path}: patched")


def patch_debug(path: Path) -> None:
    text = path.read_text()
    if 'fputs("ERROR: ", stderr)' in text:
        print(f"{path}: already patched")
        return
    text = must_replace(
        text,
        """\
#ifdef HAVE_VARARGS_MACROS
void dbg_error(char *file, int line, const char *fmt, ...)
#else
void dbg_error(const char *fmt, ...)
#endif
{
	if (dbg_file) {
		va_list ap;

		fputs("ERROR: ", dbg_file);

		va_start(ap, fmt);
		vfprintf(dbg_file, fmt, ap);
		va_end(ap);

#ifdef HAVE_VARARGS_MACROS
		fprintf(dbg_file, " (%s:%d)", file, line);
#endif

		fputs("\\n", dbg_file);
		fflush(dbg_file);
	}
}
""",
        """\
#ifdef HAVE_VARARGS_MACROS
void dbg_error(char *file, int line, const char *fmt, ...)
#else
void dbg_error(const char *fmt, ...)
#endif
{
	va_list ap;

	fputs("ERROR: ", stderr);
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
#ifdef HAVE_VARARGS_MACROS
	fprintf(stderr, " (%s:%d)", file, line);
#endif
	fputs("\\n", stderr);
	fflush(stderr);

	if (dbg_file) {
		fputs("ERROR: ", dbg_file);

		va_start(ap, fmt);
		vfprintf(dbg_file, fmt, ap);
		va_end(ap);

#ifdef HAVE_VARARGS_MACROS
		fprintf(dbg_file, " (%s:%d)", file, line);
#endif

		fputs("\\n", dbg_file);
		fflush(dbg_file);
	}
}
""",
        "debug stderr",
    )
    path.write_text(text)
    print(f"{path}: patched")


def patch_texture(path: Path) -> None:
    text = path.read_text()
    if "GL_CLAMP_TO_EDGE" in text and "glGenerateMipmap" not in text:
        print(f"{path}: already patched")
        return

    text = must_replace(
        text,
        """\
texture_t SDL_GL_LoadTexture(SDL_Surface *surface, SDL_Rect *area, int alpha, int clamp) {
	texture_t texture;
	int w, h;
	SDL_Surface *image;
	SDL_Rect dest;
	Uint32 saved_flags;
	Uint8 saved_alpha;

	/* Use the surface width and height expanded to powers of 2 */
	w = power_of_two(area->w);
	h = power_of_two(area->h);

	image = SDL_CreateRGBSurface(SDL_SWSURFACE, w, h, 32,
#if SDL_BYTEORDER == SDL_LIL_ENDIAN /* OpenGL RGBA masks */
								 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000
#else
								 0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF
#endif
	);
	if (image == NULL) {
		exit(0);
	}

	/* Copy the surface into the GL texture image */
	dest.x = 0;
	dest.y = 0;
	dest.w = area->w;
	dest.h = area->h;
	SDL_SetSurfaceBlendMode(surface, SDL_BLENDMODE_NONE);
	SDL_BlitSurface(surface, area, image, &dest);

	/* Create an OpenGL texture for the image */
	glGenTextures(1, &texture.id);
	glBindTexture(GL_TEXTURE_2D, texture.id);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);

	if (clamp) {
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
	}

	glTexImage2D(GL_TEXTURE_2D, 0, (alpha ? 4 : 3), w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, image->pixels);
	SDL_FreeSurface(image); /* No longer needed */

	glEnable(GL_TEXTURE_2D);
	glGenerateMipmap(GL_TEXTURE_2D);

	texture.u1 = 0;
	texture.v1 = 0;
	texture.u2 = area->w / (float)w;
	texture.v2 = area->h / (float)h;
	texture.width = area->w;
	texture.height = area->h;

	return texture;
}
""",
        """\
texture_t SDL_GL_LoadTexture(SDL_Surface *surface, SDL_Rect *area, int alpha, int clamp) {
	texture_t texture;
	int w, h;
	int upload_w, upload_h;
	SDL_Surface *image;
	SDL_Rect dest;
	/* vc4: mipmapped textures sample as white/grey. 2048^2 titles exhaust CMA. */
	const int max_tex = 1024;

	(void)alpha;
	upload_w = area->w;
	upload_h = area->h;
	if (upload_w > max_tex || upload_h > max_tex) {
		int max_side = upload_w > upload_h ? upload_w : upload_h;
		upload_w = upload_w * max_tex / max_side;
		upload_h = upload_h * max_tex / max_side;
		if (upload_w < 1)
			upload_w = 1;
		if (upload_h < 1)
			upload_h = 1;
	}

	w = power_of_two(upload_w);
	h = power_of_two(upload_h);

	image = SDL_CreateRGBSurface(SDL_SWSURFACE, w, h, 32,
#if SDL_BYTEORDER == SDL_LIL_ENDIAN /* OpenGL RGBA masks */
								 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000
#else
								 0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF
#endif
	);
	if (image == NULL) {
		exit(0);
	}

	dest.x = 0;
	dest.y = 0;
	dest.w = upload_w;
	dest.h = upload_h;
	SDL_SetSurfaceBlendMode(surface, SDL_BLENDMODE_NONE);
	if (upload_w != area->w || upload_h != area->h)
		SDL_BlitScaled(surface, area, image, &dest);
	else
		SDL_BlitSurface(surface, area, image, &dest);

	glGenTextures(1, &texture.id);
	glBindTexture(GL_TEXTURE_2D, texture.id);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, clamp ? GL_CLAMP_TO_EDGE : GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, clamp ? GL_CLAMP_TO_EDGE : GL_REPEAT);

	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	if (image->pitch != w * 4)
		glPixelStorei(GL_UNPACK_ROW_LENGTH, image->pitch / 4);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, image->pixels);
	glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
	glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
	SDL_FreeSurface(image);

	glEnable(GL_TEXTURE_2D);

	texture.u1 = 0;
	texture.v1 = 0;
	texture.u2 = upload_w / (float)w;
	texture.v2 = upload_h / (float)h;
	texture.width = area->w;
	texture.height = area->h;

	return texture;
}
""",
        "SDL_GL_LoadTexture",
    )

    text = must_replace(
        text,
        """\
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
""",
        """\
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
""",
        "fullscreen wrap",
    )
    path.write_text(text)
    print(f"{path}: patched")


def patch_colour_fbo(path: Path) -> None:
    text = path.read_text()
    if "get_screen_width()" in text and "GL_BGRA" not in text:
        print(f"{path}: already patched")
        return
    text = must_replace(
        text,
        """\
void init_fbo(void) {
	const int width = 1920;
	const int height = 1080;

	glGenTextures(1, &colourpicking_tex);
	glBindTexture(GL_TEXTURE_2D, colourpicking_tex);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
""",
        """\
void init_fbo(void) {
	const int width = get_screen_width();
	const int height = get_screen_height();

	glGenTextures(1, &colourpicking_tex);
	glBindTexture(GL_TEXTURE_2D, colourpicking_tex);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
""",
        "colour picking FBO",
    )
    path.write_text(text)
    print(f"{path}: patched")


def patch_screen_fbo(path: Path) -> None:
    text = path.read_text()
    if "glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, width, height);" in text and "if (ms > 0)" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(
        text,
        """\
static void init_screen_fbo_ms(int width, int height, int ms) {
	glBindFramebuffer(GL_FRAMEBUFFER, screen_fb);

	glBindRenderbuffer(GL_RENDERBUFFER, screen_color_rb);
	glRenderbufferStorageMultisample(GL_RENDERBUFFER, ms, GL_RGBA8, width, height);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, screen_color_rb);

	glBindRenderbuffer(GL_RENDERBUFFER, screen_depth_stencil_rb);
	glRenderbufferStorageMultisample(GL_RENDERBUFFER, ms, GL_DEPTH24_STENCIL8, width, height);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, screen_depth_stencil_rb);
""",
        """\
static void init_screen_fbo_ms(int width, int height, int ms) {
	glBindFramebuffer(GL_FRAMEBUFFER, screen_fb);

	glBindRenderbuffer(GL_RENDERBUFFER, screen_color_rb);
	if (ms > 0)
		glRenderbufferStorageMultisample(GL_RENDERBUFFER, ms, GL_RGBA8, width, height);
	else
		glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, width, height);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, screen_color_rb);

	glBindRenderbuffer(GL_RENDERBUFFER, screen_depth_stencil_rb);
	if (ms > 0)
		glRenderbufferStorageMultisample(GL_RENDERBUFFER, ms, GL_DEPTH24_STENCIL8, width, height);
	else
		glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, screen_depth_stencil_rb);
""",
        "screen FBO ms=0",
    )
    path.write_text(text)
    print(f"{path}: patched")


def patch_audio(path: Path) -> None:
    text = path.read_text()
    patched = False

    if "SDL audio driver:" not in text:
        text = must_replace(
            text,
            """\
	int audio_rate = 44100;
	Uint16 audio_format = AUDIO_S16;
	int audio_channels = 2;
	int audio_buffers = 4096;
	music_pack_t *music_pack;
	option_t *option;

	music_packs = theme_get_music_packs();

	if (SDL_Init(SDL_INIT_AUDIO) != 0) {
		DBG_ERROR("SDL audio initialization failed: %s", SDL_GetError());
		return;
	}

	if (Mix_OpenAudio(audio_rate, audio_format, audio_channels, audio_buffers)) {
		DBG_ERROR("Unable to open audio");
		return;
	}
""",
            """\
	int audio_rate = 44100;
	Uint16 audio_format = AUDIO_S16SYS;
	int audio_channels = 2;
	int audio_buffers = 1024;
	music_pack_t *music_pack;
	option_t *option;

	music_packs = theme_get_music_packs();

	if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
		const char *fallbacks[] = {"pulseaudio", "alsa", "dsp", NULL};
		int i;

		DBG_ERROR("SDL audio initialization failed: %s", SDL_GetError());
		for (i = 0; fallbacks[i]; i++) {
			SDL_setenv("SDL_AUDIODRIVER", fallbacks[i], 1);
			if (SDL_InitSubSystem(SDL_INIT_AUDIO) == 0)
				break;
		}
		if (!SDL_WasInit(SDL_INIT_AUDIO)) {
			DBG_ERROR("SDL audio fallbacks failed: %s", SDL_GetError());
			return;
		}
	}

	DBG_LOG("SDL audio driver: %s", SDL_GetCurrentAudioDriver());

	if (Mix_OpenAudio(audio_rate, audio_format, audio_channels, audio_buffers) != 0 &&
		Mix_OpenAudio(48000, audio_format, audio_channels, audio_buffers) != 0) {
		DBG_ERROR("Unable to open audio: %s", Mix_GetError());
		return;
	}
""",
            "audio init fallback",
        )
        patched = True

    if "continuing without this sound" not in text:
        text = must_replace(
            text,
            """\
		wav_data[sounds[i].id] = Mix_LoadWAV(sounds[i].filename);
		if (!wav_data[sounds[i].id]) {
			DBG_ERROR("Failed to load %s", sounds[i].filename);
			exit(1);
		}
""",
            """\
		wav_data[sounds[i].id] = Mix_LoadWAV(sounds[i].filename);
		if (!wav_data[sounds[i].id]) {
			DBG_ERROR("Failed to load %s; continuing without this sound", sounds[i].filename);
		}
""",
            "audio load",
        )
        if "if (!wav_data[id])" not in text:
            text = must_replace(
                text,
                """\
	if (sound_volume == 0)
		return;

	if (Mix_PlayChannel(0, wav_data[id], 0) == -1)
""",
                """\
	if (sound_volume == 0)
		return;

	if (!wav_data[id])
		return;

	if (Mix_PlayChannel(0, wav_data[id], 0) == -1)
""",
                "audio play",
            )
        patched = True

    if patched:
        path.write_text(text)
        print(f"{path}: patched")
    else:
        print(f"{path}: already patched")


HIDE_CURSOR_C = """\
	{
		SDL_Surface *blank = SDL_CreateRGBSurfaceWithFormat(0, 1, 1, 32, SDL_PIXELFORMAT_ARGB8888);
		if (blank) {
			SDL_memset(blank->pixels, 0, (size_t)blank->h * (size_t)blank->pitch);
			SDL_Cursor *hidden = SDL_CreateColorCursor(blank, 0, 0);
			if (hidden)
				SDL_SetCursor(hidden);
			SDL_FreeSurface(blank);
		}
		SDL_ShowCursor(SDL_DISABLE);
	}
"""


def patch_hide_cursor(ui_path: Path, scene_path: Path) -> None:
    text = ui_path.read_text()
    if "SDL_CreateColorCursor(blank" in text:
        print(f"{ui_path}: cursor already patched")
    else:
        text = must_replace(
            text,
            """\
		/* Draw mouse cursor.. */
		draw_texture(get_menu_mouse_cursor(), get_mouse_x(), (479 - get_mouse_y() - 32), 32, 32, 1.0f,
					 get_col(COL_WHITE));
""",
            "		/* Software mouse cursor disabled on GamerCard (no mouse). */\n",
            "menu software cursor",
        )
        text = must_replace(
            text,
            "	SDL_ShowCursor(SDL_DISABLE);\n",
            HIDE_CURSOR_C,
            "hide SDL cursor",
        )
        ui_path.write_text(text)
        print(f"{ui_path}: cursor hidden")

    text = scene_path.read_text()
    if "Software mouse cursor disabled" in text:
        print(f"{scene_path}: already patched")
        return
    text = must_replace(
        text,
        """\
	/* Draw mouse cursor.. */
	draw_texture(get_mouse_cursor(), get_mouse_x(), (479 - get_mouse_y() - 32), 32, 32, 1.0f, get_col(COL_WHITE));
""",
        "	/* Software mouse cursor disabled on GamerCard (no mouse). */\n",
        "ingame software cursor",
    )
    scene_path.write_text(text)
    print(f"{scene_path}: cursor hidden")


def patch_hud(path: Path) -> None:
    """Move captured-piece icons up and to the bezels on Hyperpixel 720x720.

    Upstream HUD is laid out for 640x480. On a square 480x480 virtual screen the
    lists sit over the player's corner pieces; tuck them under the king avatars.
    """
    text = path.read_text()
    if "GamerCard Hyperpixel: captured-piece icons" in text:
        print(f"{path}: already patched")
        return
    text = must_replace(
        text,
        "	coord3_t capture_list_offset = {60 + get_ui_trans_pos(), 180};",
        "	/* GamerCard Hyperpixel: captured-piece icons on the side bezels. */\n"
        "	coord3_t capture_list_offset = {24 + get_ui_trans_pos(), 352};",
        "capture list offset",
    )
    text = must_replace(
        text,
        "		offset.y -= 28; /*get_text_character('a')->height;*/\n",
        "		offset.y -= 24;\n",
        "capture list spacing",
    )
    path.write_text(text)
    print(f"{path}: HUD capture lists moved")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    patch_header(root / "dreamchess/src/gui/ui_sdlgl.h")
    patch_ui(root / "dreamchess/src/gui/ui_sdlgl.c")
    patch_texture(root / "dreamchess/src/gui/texture.c")
    patch_colour_fbo(root / "dreamchess/src/gui/ui_sdlgl_3d.c")
    patch_screen_fbo(root / "dreamchess/src/gui/ui_sdlgl.c")
    patch_hide_cursor(root / "dreamchess/src/gui/ui_sdlgl.c", root / "dreamchess/src/gui/draw_scene.c")
    patch_hud(root / "dreamchess/src/gui/ingame_ui.c")
    patch_cmake(root / "dreamchess/src/CMakeLists.txt")
    patch_debug(root / "dreamchess/src/debug.c")
    patch_audio(root / "dreamchess/src/audio/sdlmixer.c")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
