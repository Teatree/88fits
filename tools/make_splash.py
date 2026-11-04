"""The boot splash: plain paper (pass 118, lane LOAD; Garry: "No icon, No progress bar. Title Drop sequence at the
start and an animation of silhuettes ... This is meant to be the new progress bar replacement showing that the game is
loading").

Godot's boot splash shows nothing but its bg_color now: project.godot `application/boot_splash/show_image=false` (the
engine then draws only `bg_color`, which is the Wanted paper, W.PAPER) and no picture. The loading screen
(game/ui/Boot.gd) starts on that same paper on any screen and fades its saloon wallpaper in from it, then drops the
title in (its pictures: tools/make_loading_wallpaper.py). Until pass 117 the splash was a picture of the loading screen
at 0 % (the launcher painting in a disc, the name, an empty bar; passes 54 and 58), which Boot.gd redrew to the pixel.

Android's own splash screen (Android 12 and up, the theme's windowSplashScreenAnimatedIcon) shows the export preset's
`splash_screen/icon` on `splash_screen/background_color`. The icon is now `game/art/ui/splash_icon.png`, 768 x 768 and
transparent in every pixel, so that splash is the paper alone. (Left empty, the option would fall back to an icon; a
picture drawn clear is what the theme can show as nothing.)

This tool writes that icon and checks the rest: the boot splash's settings in project.godot and the Android presets'
splash background are the paper, read from W.gd.

  python tools/make_splash.py
"""
import os
import re
import sys

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(REPO, "game")
OUT_ICON = os.path.join(GAME, "art", "ui", "splash_icon.png")
OLD_SPLASH = os.path.join(GAME, "art", "ui", "splash.png")
ICON_CANVAS = 768


def w_color(name):
    """A colour constant of the Wanted UI kit (`const NAME := Color("rrggbb")` in W.gd) as an RGB tuple."""
    src = open(os.path.join(GAME, "ui", "wanted", "W.gd"), encoding="utf-8").read()
    m = re.search(r'^const %s := Color\("([0-9a-fA-F]{6})"\)' % name, src, re.M)
    if not m:
        raise SystemExit("W.gd has no %s" % name)
    h = m.group(1)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def godot_color(text):
    """`Color(r, g, b, a)` as written in project.godot / export_presets.cfg, as 8-bit RGB."""
    v = [float(x) for x in re.findall(r"[-0-9.]+", text)[:3]]
    return tuple(round(c * 255) for c in v)


def splash_icon():
    img = Image.new("RGBA", (ICON_CANVAS, ICON_CANVAS), (0, 0, 0, 0))
    img.save(OUT_ICON, optimize=True)
    print("splash icon: %s %dx%d, clear (Android's splash shows its background alone)" % (
        OUT_ICON, ICON_CANVAS, ICON_CANVAS))


def check():
    # pass 124: the dark loading screen's colour (ui/Boot.gd's DARK), not the paper any more
    paper = (11, 16, 32)
    bad = []
    proj = open(os.path.join(GAME, "project.godot"), encoding="utf-8").read()
    m = re.search(r"^boot_splash/bg_color=(.*)$", proj, re.M)
    if not m or godot_color(m.group(1)) != paper:
        bad.append("project.godot boot_splash/bg_color is not the paper %s" % (paper,))
    if not re.search(r"^boot_splash/show_image=false$", proj, re.M):
        bad.append("project.godot boot_splash/show_image is not false")
    if re.search(r"^boot_splash/image=", proj, re.M):
        bad.append("project.godot still names a boot_splash/image")
    presets = open(os.path.join(GAME, "export_presets.cfg"), encoding="utf-8").read()
    for m in re.finditer(r"^splash_screen/background_color=(.*)$", presets, re.M):
        if godot_color(m.group(1)) != paper:
            bad.append("export_presets.cfg: an Android splash background is not the paper")
    for m in re.finditer(r'^splash_screen/icon="([^"]*)"$', presets, re.M):
        if m.group(1) != "res://art/ui/splash_icon.png":
            bad.append("export_presets.cfg: an Android splash icon is %s" % m.group(1))
    if bad:
        raise SystemExit("make_splash: " + "; ".join(bad))
    print("splash: Godot's boot splash is the paper %s alone; the Android presets' splash is the same paper" % (paper,))
    if os.path.exists(OLD_SPLASH):
        print("note: %s (the old splash picture) is no longer used" % OLD_SPLASH)


if __name__ == "__main__":
    splash_icon()
    check()
    sys.exit(0)
