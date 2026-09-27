#!/usr/bin/env python3
# Generates the pre-2000 style logo test in assets/logo/retro from a 32x32 silhouette mask.
# Usage: scripts/logo/retro.py MASK OUTDIR   (MASK: 32 lines of 32 chars, 0 = potato)
import sys

mask = [[c == '0' for c in l.strip()] for l in open(sys.argv[1])]
outdir = sys.argv[2]
N = 32
OUT, BODY, SHADE, LIGHT = '#4a2a10', '#d9a05b', '#b07a3c', '#f2cd98'


def inside(x, y):
    return 0 <= x < N and 0 <= y < N and mask[y][x]


px = {}
for y in range(N):
    for x in range(N):
        if not inside(x, y):
            continue
        if any(not inside(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            px[(x, y)] = OUT
            continue
        # the distance to the lower right edge gives the shaded side, dithered like a 16 color icon
        d = min([k for k in range(1, 8) if not inside(x + k, y + k)] or [9])
        c = SHADE if d <= 2 or (d == 3 and (x + y) % 2 == 0) else BODY
        u = min([k for k in range(1, 8) if not inside(x - k, y - k)] or [9])
        if u == 2 and 9 <= x <= 17 and y <= 14:
            c = LIGHT
        px[(x, y)] = c
for p in [(11, 15), (12, 15), (18, 12), (19, 12), (21, 17), (22, 17), (14, 20), (15, 20), (8, 18)]:
    if px.get(p) in (BODY, SHADE):
        px[p] = OUT


def rects(scale=1, ox=0, oy=0):
    out = []
    for y in range(N):
        x = 0
        while x < N:
            c = px.get((x, y))
            if c is None:
                x += 1
                continue
            x2 = x
            while x2 + 1 < N and px.get((x2 + 1, y)) == c:
                x2 += 1
            out.append(f'<rect x="{ox + x * scale}" y="{oy + y * scale}" width="{(x2 - x + 1) * scale}" height="{scale}" fill="{c}"/>')
            x = x2 + 1
    return '\n    '.join(out)


FONT = {
    'A': ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    'C': ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    'D': ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    'E': ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    'F': ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    'G': ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    'H': ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    'I': ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    'L': ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    'M': ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    'N': ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    'O': ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    'P': ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    'R': ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    'S': ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    'T': ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    'K': ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    'U': ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    '3': ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    '-': ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    '(': ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
    ')': ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
    ':': ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    ',': ["00000", "00000", "00000", "00000", "01100", "00100", "01000"],
    'X': ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    '4': ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    '5': ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    '6': ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    'W': ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    'Y': ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    '2': ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
    '0': ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    '.': ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    ' ': ["00000"] * 7,
}


def text(s, x, y, scale, fill):
    out = []
    for i, ch in enumerate(s):
        for r, row in enumerate(FONT[ch]):
            c = 0
            while c < 5:
                if row[c] != '1':
                    c += 1
                    continue
                c2 = c
                while c2 + 1 < 5 and row[c2 + 1] == '1':
                    c2 += 1
                out.append(f'<rect x="{x + (i * 6 + c) * scale}" y="{y + r * scale}" width="{(c2 - c + 1) * scale}" height="{scale}" fill="{fill}"/>')
                c = c2 + 1
    return '\n    '.join(out)


HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'
open(f'{outdir}/hypoland-retro.svg', 'w').write(HEAD + f'''<!-- Hypoland logo, pre-2000 test: a 32x32 pixel icon with 4 colors. Generated by scripts/logo/retro.py. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="256" height="256" shape-rendering="crispEdges" role="img" aria-label="Hypoland">
  <title>Hypoland</title>
  <g>
    {rects()}
  </g>
</svg>
''')


# The O is what turns Hyprland into Hypoland, so it is a small potato drawn at half the letter pixel size.
# Hypo- means under, so it hangs below the baseline like a subscript.
O_SPRITE = [
    "......XXXX...",
    "....XXLLBBX..",
    "...XLLBBBBSX.",
    "..XLLBBBBBBSX",
    ".XLLBBBBEEBSX",
    ".XLBBBBBBBBSX",
    "XLBBBBBBBBBSX",
    "XLBBBBBBBBBSX",
    "XBEEBBBBBBSSX",
    "XBBBBBBBBBBSX",
    "XBBBBBBBBEESX",
    "XBBBBBBBBBSX.",
    "XBBBBBBBBBSX.",
    ".XBBEEBBBSSX.",
    ".XSBBBBBSSX..",
    "..XXSSSSSX...",
    "....XXXXX....",
]
O_COLORS = {'X': OUT, 'B': BODY, 'S': SHADE, 'L': LIGHT, 'E': OUT}


def sprite(rows, x, y, scale, colors):
    out = []
    for r, row in enumerate(rows):
        c = 0
        while c < len(row):
            if row[c] not in colors:
                c += 1
                continue
            c2 = c
            while c2 + 1 < len(row) and colors.get(row[c2 + 1]) == colors[row[c]]:
                c2 += 1
            out.append(f'<rect x="{x + c * scale}" y="{y + r * scale}" width="{(c2 - c + 1) * scale}" height="{scale}" fill="{colors[row[c]]}"/>')
            c = c2 + 1
    return '\n    '.join(out)


def word(s, x, y, scale, fill, shadow):
    # bitmap word with a drop shadow, the O is replaced by the potato
    out = []
    for i, ch in enumerate(s):
        cx = x + i * 6 * scale
        if ch == 'O':
            # 40 px of the 68 px potato above the baseline, 28 below: 1.43, the closest the pixel grid gets to the golden ratio
            out.append(sprite(O_SPRITE, cx - scale, y + 2 * scale, scale // 2, O_COLORS))
            continue
        out.append(text(ch, cx + scale // 2, y + scale // 2, scale, shadow))
        out.append(text(ch, cx, y, scale, fill))
    return '\n    '.join(out)


W, H = 760, 240
TAGLINE = "WAYLAND COMPOSITOR FOR OPENGL ES 2.0"
WS, TS = 14, 3  # pixel size of the word and of the tagline, both centered
open(f'{outdir}/header-retro.svg', 'w').write(HEAD + f'''<!-- Hypoland banner, pre-2000 test: bitmap lettering whose O is a pixel potato. Generated by scripts/logo/retro.py. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" shape-rendering="crispEdges" role="img" aria-label="Hypoland">
  <title>Hypoland</title>
  <g>
    {word("HYPOLAND", (W - 47 * WS) // 2, 20, WS, "#8a8f98", "#3a3f48")}
  </g>
  <g>
    {text(TAGLINE, (W - (6 * len(TAGLINE) - 1) * TS) // 2, 196, TS, "#8a8f98")}
  </g>
</svg>
''')
