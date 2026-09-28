#!/usr/bin/env python3
# Generates the screens the compositor shows when the lock screen app dies, in assets/install:
#   lockdead.png   the lock app is gone: banner and instructions to unlock from another tty
#   lockdead2.png  a lock surface still exists: a dim banner only
# The banner is the retro one (assets/logo/retro/header-retro.svg), recolored for a dark background.
# Usage: scripts/logo/lockdead.py [REPO]   (needs pycairo, draws with the system "sans" and "monospace" fonts)
import re
import sys
from pathlib import Path

import cairo

repo = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])
W, H = 1920, 1080
BG = (0.04, 0.04, 0.04)
TEXT = (0.72, 0.72, 0.72)
CODE = (0.85, 0.63, 0.36)

# the lettering face was dark grey for a light background
RECOLOR = {'#8a8f98': '#c8ccd3'}

svg = (repo / 'assets/logo/retro/header-retro.svg').read_text()
RECTS = [(float(x), float(y), float(w), float(h), RECOLOR.get(c, c))
         for x, y, w, h, c in re.findall(r'<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)" fill="(#[0-9a-f]{6})"/>', svg)]


def rgb(c):
    return tuple(int(c[i:i + 2], 16) / 255 for i in (1, 3, 5))


def banner(cr, cx, top, scale, alpha):
    cr.save()
    cr.translate(cx - 760 * scale / 2, top)
    cr.scale(scale, scale)
    for x, y, w, h, c in RECTS:
        cr.set_source_rgba(*rgb(c), alpha)
        cr.rectangle(x, y, w, h)
        cr.fill()
    cr.restore()


def line(cr, text, y, size, color, font='sans'):
    cr.select_font_face(font, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    cr.set_font_size(size)
    ext = cr.text_extents(text)
    cr.move_to((W - ext.x_advance) / 2, y)
    cr.set_source_rgb(*color)
    cr.show_text(text)


def canvas():
    surface = cairo.ImageSurface(cairo.FORMAT_RGB24, W, H)
    cr = cairo.Context(surface)
    cr.set_source_rgb(*BG)
    cr.paint()
    # crisp pixel art, smooth text
    cr.set_antialias(cairo.ANTIALIAS_NONE)
    return surface, cr


out = repo / 'assets/install'

surface, cr = canvas()
banner(cr, W / 2, 40, 1.25, 1.0)
cr.set_antialias(cairo.ANTIALIAS_DEFAULT)
y = 400
for text, size, color, font, gap in [
    ("Oops, it looks like you locked your screen, but the lock screen app died :(", 38, TEXT, 'sans', 90),
    ("To unlock your screen, go to another tty (e.g. Ctrl+Alt+F3), log in, and run:", 34, TEXT, 'sans', 56),
    ("hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'", 34, CODE, 'monospace', 90),
    ("If that doesn't help, kill what is left of your lock screen app, e.g.", 34, TEXT, 'sans', 56),
    ("pkill -9 quickshell  (the Omarchy shell)   or   pkill -9 hyprlock", 30, CODE, 'monospace', 50),
    ("then run the eval command again.", 34, TEXT, 'sans', 90),
    ("Once your session is unlocked, press Ctrl+D (or run exit) in that tty to log out.", 34, TEXT, 'sans', 90),
    ("You can come back to Hypoland with Ctrl+Alt+F[N], where N is the tty number in the top left corner.", 30, TEXT, 'sans', 0),
]:
    line(cr, text, y, size, color, font)
    y += gap
surface.write_to_png(str(out / 'lockdead.png'))

surface, cr = canvas()
banner(cr, W / 2, (H - 240 * 1.5) / 2, 1.5, 0.18)
surface.write_to_png(str(out / 'lockdead2.png'))
