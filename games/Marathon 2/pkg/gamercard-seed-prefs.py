#!/usr/bin/env python3
"""GamerCard: one-time preference fixes for the Hyperpixel 4.0 + Leonardo pad.

Confirmed on the real hardware (Pi Zero 2 W, Debian 12 aarch64, labwc):
Aleph One writes its preferences to "~/.alephone/Marathon 2 Preferences",
an XML document rooted at <mara_prefs> with <graphics> and <input> children
(see Source_Files/Misc/preferences.cpp upstream).

This script is invoked by pkg/marathon2 on every launch, but each fix below
only ever touches the preferences file ONCE, guarded by its own sentinel
file next to it. That matters for two reasons:

  1. Aleph One's own write_preferences() rewrites each preferences node from
     its in-memory struct every time it saves (e.g. leaving the Preferences
     dialog, or quitting), so any attribute/binding we add that Aleph One
     doesn't already know about would simply be dropped on the next save. A
     sentinel file living outside the XML survives that.

  2. Once the player has a working menu and gamepad, they may deliberately
     change resolution or rebind controls themselves from the Preferences
     screens. We must not silently revert those changes on a later launch,
     so each fix seeds only once: on a brand new install (no prefs file
     yet) AND on an upgrade from an older, unpatched package version.

Three independent fixes, three independent sentinel files (so upgrading an
existing GamerCard install applies each new fix without re-touching the
ones that already ran):

  * 720x720 fullscreen graphics (scmode_* attributes on <graphics>).

  * Trigger (fire) bindings. Aleph One's default "trigger-1"/"trigger-2"
    (primary/secondary weapon fire) actions read the controller's analog
    trigger axes (controller-rt/controller-lt), which the GamerCard pad
    doesn't have. Aliasing a real button to a virtual trigger axis in
    SDL_GAMECONTROLLERCONFIG (e.g. "righttrigger:b1" alongside "b:b1")
    does not work -- SDL only ever fires the FIRST binding that matches a
    given physical button, so "b:b1" always wins and the alias is dead
    code. So pkg/marathon2 leaves B/Back as plain buttons, and this script
    rebinds "trigger-1"/"trigger-2" straight to "controller-b"/
    "controller-back" instead (confirmed working on real hardware: B
    didn't fire until this rebind, even though B was clearly recognized
    as a button -- X already opened the map fine via its own default
    "controller-x" binding, which doesn't have this axis-aliasing problem).

  * D-pad-based movement bindings. The GamerCard's "stick" (SDL axes a0/a1)
    is actually a 4-way digital D-pad wired as two analog axes (confirmed
    with `jstest`: each axis only ever reports 0 or +/-32767, never values
    in between). SDL2 cannot make one physical axis serve both a continuous
    axis (rightx/lefty) and a digital d-pad (dpup/dpdown/dpleft/dpright) at
    the same time -- SDL_gamecontroller.c's HandleJoystickAxis() only ever
    fires the FIRST matching binding for a given axis, and a full-range
    binding like "rightx:a0" matches every possible value, permanently
    starving the half-range dpad bindings. Aleph One's main-menu navigation
    (and its "glance"/"map zoom" actions) are hardcoded to read real
    SDL_CONTROLLER_BUTTON_DPAD_* button presses, so pkg/marathon2 dedicates
    a0/a1 to the d-pad only (no rightx/lefty in SDL_GAMECONTROLLERCONFIG
    any more). That means Aleph One's *default* "forward"/"back"/
    "look-left"/"look-right" bindings (which read the now-gone continuous
    axis) go dead, so we rebind those 4 actions here to read the d-pad
    buttons directly instead: up=forward, down=back, left=turn-left,
    right=turn-right ("tank controls"). We also clear any controller
    binding on "glance-left/right" and "map-zoom-in/out", which default to
    those same buttons, to avoid one press triggering two actions at once.
    These are minor, rarely-used actions -- an acceptable trade-off for
    working menu navigation *and* movement on a single D-pad.

Uses only the standard library (xml.etree.ElementTree), so it needs no
extra runtime dependency beyond python3 itself.
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

GRAPHICS_MARKER_NAME = ".gamercard_720p_seeded"
GRAPHICS_DEFAULTS = {
    "scmode_width": "720",
    "scmode_height": "720",
    "scmode_auto_resolution": "false",
    "scmode_fullscreen": "true",
    "scmode_high_dpi": "false",
}

TRIGGER_MARKER_NAME = ".gamercard_trigger_controls_seeded"
# action -> real-button binding, replacing the analog-trigger-axis binding
# these actions use by default (controller-rt/controller-lt), which the
# GamerCard pad cannot drive (see module docstring).
TRIGGER_BUTTON_BINDINGS = {
    "trigger-1": "controller-b",
    "trigger-2": "controller-back",
}

CONTROLS_MARKER_NAME = ".gamercard_dpad_controls_seeded"
# action -> new d-pad-button binding ("tank controls": up/down = walk,
# left/right = turn), replacing the continuous-axis binding these actions
# use by default (controller-ls-up/down, controller-rs-left/right).
DPAD_MOVEMENT_BINDINGS = {
    "forward": "controller-up",
    "back": "controller-down",
    "look-left": "controller-left",
    "look-right": "controller-right",
}
# Actions that default to the same physical d-pad buttons we just
# repurposed above; drop their controller binding so a single press doesn't
# also fire one of these secondary actions.
ACTIONS_TO_UNBIND_FROM_CONTROLLER = {
    "glance-left",
    "glance-right",
    "map-zoom-in",
    "map-zoom-out",
}


def load_prefs(prefs_path: Path) -> ET.ElementTree:
    if prefs_path.exists():
        try:
            tree = ET.parse(prefs_path)
            if tree.getroot().tag != "mara_prefs":
                raise ET.ParseError(f"unexpected root <{tree.getroot().tag}>")
            return tree
        except ET.ParseError as ex:
            print(f"{prefs_path}: could not parse ({ex}), recreating", file=sys.stderr)
    return ET.ElementTree(ET.Element("mara_prefs"))


def seed_graphics(root: ET.Element) -> None:
    graphics = root.find("graphics")
    if graphics is None:
        graphics = ET.SubElement(root, "graphics")
    for key, value in GRAPHICS_DEFAULTS.items():
        graphics.set(key, value)


def _get_or_create_input(root: ET.Element) -> ET.Element:
    input_el = root.find("input")
    if input_el is None:
        input_el = ET.SubElement(root, "input")
    return input_el


def _replace_controller_bindings(
    input_el: ET.Element,
    new_bindings: dict,
    also_clear_actions: set = frozenset(),
) -> None:
    """Remove any existing controller-* binding for the given actions (and
    for any extra actions in also_clear_actions), then add the bindings in
    new_bindings. Keyboard/mouse bindings for these actions are untouched.
    """
    actions_touched = set(new_bindings) | set(also_clear_actions)
    for binding in list(input_el.findall("binding")):
        action = binding.get("action")
        pressed = binding.get("pressed", "")
        if action in actions_touched and pressed.startswith("controller-"):
            input_el.remove(binding)

    for action, pressed in new_bindings.items():
        new_binding = ET.SubElement(input_el, "binding")
        new_binding.set("action", action)
        new_binding.set("pressed", pressed)


def seed_trigger_bindings(root: ET.Element) -> None:
    _replace_controller_bindings(_get_or_create_input(root), TRIGGER_BUTTON_BINDINGS)


def seed_controller_bindings(root: ET.Element) -> None:
    _replace_controller_bindings(
        _get_or_create_input(root),
        DPAD_MOVEMENT_BINDINGS,
        also_clear_actions=ACTIONS_TO_UNBIND_FROM_CONTROLLER,
    )


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: gamercard-seed-prefs.py <prefs-file>", file=sys.stderr)
        return 1

    prefs_path = Path(sys.argv[1])
    prefs_dir = prefs_path.parent
    graphics_marker = prefs_dir / GRAPHICS_MARKER_NAME
    trigger_marker = prefs_dir / TRIGGER_MARKER_NAME
    controls_marker = prefs_dir / CONTROLS_MARKER_NAME

    need_graphics = not graphics_marker.exists()
    need_trigger = not trigger_marker.exists()
    need_controls = not controls_marker.exists()
    if not need_graphics and not need_trigger and not need_controls:
        return 0

    tree = load_prefs(prefs_path)
    root = tree.getroot()

    if need_graphics:
        seed_graphics(root)
    if need_trigger:
        seed_trigger_bindings(root)
    if need_controls:
        seed_controller_bindings(root)

    prefs_dir.mkdir(parents=True, exist_ok=True)
    tree.write(prefs_path, encoding="utf-8", xml_declaration=True)

    if need_graphics:
        graphics_marker.write_text("Seeded 720x720 fullscreen for the Hyperpixel 4.0 panel.\n")
        print(f"{prefs_path}: seeded 720x720 fullscreen (one-time)")
    if need_trigger:
        trigger_marker.write_text("Seeded controller-b/controller-back fire bindings.\n")
        print(f"{prefs_path}: seeded trigger button bindings (one-time)")
    if need_controls:
        controls_marker.write_text("Seeded d-pad tank-controls movement bindings.\n")
        print(f"{prefs_path}: seeded d-pad movement bindings (one-time)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
