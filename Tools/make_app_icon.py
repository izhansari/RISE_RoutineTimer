#!/usr/bin/env python3
"""
Generates the RISE app icon.

A dot-matrix sunrise, built as a sibling to the FLIP timer's dot-matrix
hourglass (../TwoMinRuleTimer): the same construction — one iconic object
drawn as discrete dots on a square grid, black on white, generous margins.
Where FLIP draws time running out, RISE draws the sun over a rule, the same
rule the timer screen draws under the step name.

Three appearances are written, matching the AppIcon set's Light / Dark /
Tinted slots. Dark is a straight inversion, which is what the running timer
does to its own type as the fill rises.

Run:  python3 Tools/make_app_icon.py RISE_RoutineTimer/Assets.xcassets/AppIcon.appiconset

Design notes, so the wheel is not reinvented:
  · An outlined *arc* sitting on the horizon reads as a tent, not a sun —
    at this dot pitch a shallow curve has no curvature to speak of.
  · A *filled* disc reads as a stepped pyramid.
  · A small outlined circle (radius < 4 cells) rasters closer to a rounded
    square than a circle.
  · Walking the ring by angle and rounding doubles dots on the diagonals and
    looks lumpy; take one dot per column and per row instead.
"""

import math
import sys
from PIL import Image, ImageDraw

SIZE = 1024
SUN_RADIUS = 5          # cells
RAY_DEGREES = (0, 45, 90, 135, 180)
RAY_GAPS = (2.2, 3.4)   # cells beyond the ring, inner and outer dot
HORIZON_HALF_WIDTH = 8  # cells either side of centre
MARGIN = 0.13           # fraction of the canvas left empty on each side
DOT_FRACTION = 0.36     # dot radius as a fraction of the grid pitch


def ring(center_row, radius):
    cells = set()
    for col in range(-radius, radius + 1):
        offset = round(math.sqrt(max(radius * radius - col * col, 0)))
        cells.add((col, center_row - offset))
        cells.add((col, center_row + offset))
    for offset in range(-radius, radius + 1):
        col = round(math.sqrt(max(radius * radius - offset * offset, 0)))
        cells.add((-col, center_row + offset))
        cells.add((col, center_row + offset))
    return cells


def rays(center_row, radius):
    cells = set()
    for degrees in RAY_DEGREES:
        radians = math.radians(degrees)
        for gap in RAY_GAPS:
            distance = radius + gap
            cells.add((
                round(math.cos(radians) * distance),
                round(center_row - math.sin(radians) * distance),
            ))
    return cells


def horizon():
    return {(col, 0) for col in range(-HORIZON_HALF_WIDTH, HORIZON_HALF_WIDTH + 1)}


def build():
    # Three rows of clearance between the sun and the rule it rises over.
    center_row = -(SUN_RADIUS + 3)
    return ring(center_row, SUN_RADIUS) | rays(center_row, SUN_RADIUS) | horizon()


def render(cells, path, dot, background):
    image = Image.new("RGB", (SIZE, SIZE), background)
    draw = ImageDraw.Draw(image)

    cols = [c for c, _ in cells]
    rows = [r for _, r in cells]
    span = max(max(cols) - min(cols), max(rows) - min(rows))
    pitch = SIZE * (1 - 2 * MARGIN) / span
    dot_radius = pitch * DOT_FRACTION

    origin_x = SIZE / 2 - ((max(cols) + min(cols)) / 2) * pitch
    origin_y = SIZE / 2 - ((max(rows) + min(rows)) / 2) * pitch

    for col, row in sorted(cells):
        x = origin_x + col * pitch
        y = origin_y + row * pitch
        draw.ellipse([x - dot_radius, y - dot_radius, x + dot_radius, y + dot_radius], fill=dot)

    image.save(path)
    print("wrote", path)


if __name__ == "__main__":
    out = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "."
    cells = build()
    render(cells, f"{out}/icon-light.png", (0, 0, 0), (255, 255, 255))
    render(cells, f"{out}/icon-dark.png", (255, 255, 255), (10, 10, 10))
    render(cells, f"{out}/icon-tinted.png", (255, 255, 255), (10, 10, 10))
