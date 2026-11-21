#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Render the omarchy-trace Plymouth frames from Omarchy's own logo: its
# outline is drawn progressively, then the filled logo fades in on top; the
# last frame is the logo file unchanged.
#
#   python3 -I tools/gen-plymouth-trace.py LOGO.png OUTDIR [CONTACT_SHEET.png]
#
# LOGO.png is Omarchy's Plymouth logo, default/plymouth/logo.png in
# https://github.com/basecamp/omarchy (MIT; git blob f185b266, the same
# file omarchy-settings installs as /usr/share/plymouth/themes/omarchy/logo.png).
# Frames keep the logo's own size (800x188), as Omarchy's theme does: husky
# boots with plymouth.force-scale=1, so they sit centred on the 1344x2992
# panel at the same size as the static splash. Needs Pillow only.
import shutil
import sys
from collections import deque
from PIL import Image, ImageDraw

TRACE_FRAMES = 24
FILL_FRAMES = 6
DOT = 2  # outline half-width in pixels


def edge_pixels(alpha):
    w, h = alpha.size
    px = alpha.load()
    inside = lambda x, y: 0 <= x < w and 0 <= y < h and px[x, y] > 127
    return {(x, y) for y in range(h) for x in range(w) if inside(x, y) and not all(
        inside(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))}


def components(edges):
    left, out = set(edges), []
    while left:
        start = min(left)
        left.discard(start)
        comp, queue = [start], deque([start])
        while queue:
            x, y = queue.popleft()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (x + dx, y + dy)
                    if n in left:
                        left.discard(n)
                        comp.append(n)
                        queue.append(n)
        out.append(comp)
    return out


def walk(comp):
    """Order a component's pixels as a pen would draw them."""
    left = set(comp)
    cur = min(left, key=lambda p: (p[0], p[1]))
    left.discard(cur)
    path = [cur]
    while left:
        x, y = cur
        nxt = next(((x + dx, y + dy) for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1),
                    (1, 1), (-1, 1), (-1, -1), (1, -1)) if (x + dx, y + dy) in left), None)
        if nxt is None:
            nxt = min(left, key=lambda p: (p[0] - x) ** 2 + (p[1] - y) ** 2)
        left.discard(nxt)
        path.append(nxt)
        cur = nxt
    return path


def main():
    logo_path, outdir = sys.argv[1], sys.argv[2]
    logo = Image.open(logo_path).convert("RGBA")
    color = max(c for c in logo.getcolors(1 << 20) if c[1][3] == 255)[1]
    paths = [walk(c) for c in components(edge_pixels(logo.getchannel("A")))]
    outline = Image.new("RGBA", logo.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(outline)
    done = [0] * len(paths)
    frames = []
    for k in range(1, TRACE_FRAMES + 1):
        for i, p in enumerate(paths):
            upto = round(len(p) * k / TRACE_FRAMES)
            for x, y in p[done[i]:upto]:
                draw.ellipse((x - DOT, y - DOT, x + DOT, y + DOT), fill=color)
            done[i] = upto
        frames.append(outline.copy())
    for k in range(1, FILL_FRAMES + 1):
        fill = logo.copy()
        fill.putalpha(fill.getchannel("A").point(lambda a: a * k // FILL_FRAMES))
        frames.append(Image.alpha_composite(outline, fill))
    # The last frame is Omarchy's logo itself, with no outline halo, so the
    # held end state is exactly the static splash.
    frames[-1] = logo.copy()
    for n, f in enumerate(frames[:-1], 1):
        f.save(f"{outdir}/trace-{n:02d}.png", optimize=True)
    shutil.copyfile(logo_path, f"{outdir}/trace-{len(frames):02d}.png")
    print(f"{len(frames)} frames, {logo.size[0]}x{logo.size[1]}, {len(paths)} strokes")
    if len(sys.argv) > 3:
        cols, scale = 6, 4
        tw, th = logo.size[0] // scale, logo.size[1] // scale
        sheet = Image.new("RGBA", (cols * (tw + 8), -(-len(frames) // cols) * (th + 8)), (26, 27, 38, 255))
        for n, f in enumerate(frames):
            sheet.alpha_composite(f.resize((tw, th)), (n % cols * (tw + 8) + 4, n // cols * (th + 8) + 4))
        sheet.save(sys.argv[3])


if __name__ == "__main__":
    main()
