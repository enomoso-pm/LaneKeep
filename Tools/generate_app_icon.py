#!/usr/bin/env python3
"""Draws LaneKeep's app icon and writes every size of the macOS AppIcon set.

The icon follows the macOS icon grid: a 1024 px canvas with an 824 px rounded square
(continuous corners approximated by a superellipse) and a soft drop shadow. The glyph shows
a monitor with a window layout and a second, portrait display in the display2 color.

Usage: python3 Tools/generate_app_icon.py [output AppIcon.appiconset directory]
Requires Pillow.
"""

import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SCALE = 4  # supersampling factor
SIZE = 1024
BODY = 824
MARGIN = (SIZE - BODY) // 2


def superellipse(cx, cy, half_w, half_h, n=5.0, steps=720):
    points = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = cx + half_w * math.copysign(abs(c) ** (2 / n), c)
        y = cy + half_h * math.copysign(abs(s) ** (2 / n), s)
        points.append((x, y))
    return points


def hex_rgb(value, alpha=255):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def vertical_gradient(width, height, top, bottom):
    gradient = Image.new("RGBA", (width, height))
    draw = ImageDraw.Draw(gradient)
    for y in range(height):
        t = y / max(1, height - 1)
        color = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(4))
        draw.line([(0, y), (width, y)], fill=color)
    return gradient


def s(value):
    return value * SCALE


# The glyph is drawn slightly below the geometric center so that it looks centered with its stand.
GLYPH_OFFSET_Y = 22


def rect(draw, box, radius, fill):
    x0, y0, x1, y1 = box
    y0 += GLYPH_OFFSET_Y
    y1 += GLYPH_OFFSET_Y
    draw.rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], radius=s(radius), fill=fill)


def draw_icon():
    canvas = SIZE * SCALE
    icon = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))

    # Body mask.
    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).polygon(
        superellipse(canvas / 2, canvas / 2, s(BODY) / 2, s(BODY) / 2), fill=255
    )

    # Drop shadow of the body.
    shadow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    shadow_mask = mask.filter(ImageFilter.GaussianBlur(s(14)))
    shadow.putalpha(shadow_mask.point(lambda a: int(a * 0.32)))
    icon.alpha_composite(shadow, (0, s(10)))

    # Background gradient, clipped to the body.
    background = vertical_gradient(canvas, canvas, hex_rgb("#3F72E3"), hex_rgb("#1C46A8"))
    sheen = Image.new("RGBA", (canvas, canvas), (255, 255, 255, 0))
    ImageDraw.Draw(sheen).ellipse(
        [s(-200), s(-560), s(SIZE + 200), s(440)], fill=(255, 255, 255, 30)
    )
    background.alpha_composite(sheen.filter(ImageFilter.GaussianBlur(s(60))))
    body = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    body.paste(background, (0, 0), mask)
    icon.alpha_composite(body)

    # Glyph layer (white devices), drawn separately for its own soft shadow.
    glyph = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    g = ImageDraw.Draw(glyph)
    white = (255, 255, 255, 255)

    # Monitor with stand.
    rect(g, (190, 296, 652, 612), 36, white)
    rect(g, (398, 606, 446, 668), 6, white)
    rect(g, (326, 662, 518, 692), 15, white)
    # Portrait display.
    rect(g, (688, 262, 834, 642), 32, white)

    glyph_shadow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    glyph_shadow.putalpha(glyph.split()[3].filter(ImageFilter.GaussianBlur(s(12))).point(lambda a: int(a * 0.28)))
    icon.alpha_composite(glyph_shadow, (0, s(10)))
    icon.alpha_composite(glyph)

    # Screens and windows.
    d = ImageDraw.Draw(icon)
    rect(d, (214, 320, 628, 588), 18, hex_rgb("#E7EEFC"))
    rect(d, (232, 338, 418, 570), 12, hex_rgb("#2457C5"))
    rect(d, (432, 338, 610, 446), 12, hex_rgb("#5A86E6"))
    rect(d, (432, 460, 610, 570), 12, hex_rgb("#93B2F1"))

    rect(d, (706, 280, 816, 624), 20, hex_rgb("#FBE9DB"))
    rect(d, (720, 294, 802, 450), 11, hex_rgb("#D9732C"))
    rect(d, (720, 464, 802, 610), 11, hex_rgb("#F1B07F"))

    return icon.resize((SIZE, SIZE), Image.LANCZOS)


SIZES = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "LaneKeep", "Assets.xcassets", "AppIcon.appiconset"
    )
    os.makedirs(output, exist_ok=True)
    master = draw_icon()
    images = []
    for points, scale in SIZES:
        pixels = points * scale
        filename = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        master.resize((pixels, pixels), Image.LANCZOS).save(os.path.join(output, filename))
        images.append({
            "filename": filename,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{points}x{points}",
        })
    with open(os.path.join(output, "Contents.json"), "w") as handle:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, handle, indent=2)
        handle.write("\n")


if __name__ == "__main__":
    main()
