#!/usr/bin/env python3
"""Assemble Phase 1 decision boards from the rendered mockups.

  LX_RENDER_DIR=<dir> swift test --filter Render   (in Packages/LifeOSDesign)
  python3 design/tools/contact_sheet.py <dir> docs/uiux-plan/phase1/boards

Writes:
  compare-<artefact>.png   one artefact, three directions side by side (primary mode)
  direction-<id>.png       all six artefacts for one direction, dark and light
  orb-states.png           every orb state, every direction, both modes
Needs Pillow (pip install pillow).
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

DIRECTIONS = [("obsidian", "Obsidian & Champagne", "dark"), ("porcelain", "Porcelain", "light"), ("aurora", "Aurora Glass", "dark")]
PHONE = ["today", "capture", "mealResult", "workoutSynced"]
SMALL = ["appIcon", "watch"]
BG = (24, 24, 27)
FG = (235, 235, 240)


def font(size):
    for p in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()


def scaled(img, width):
    h = int(img.height * width / img.width)
    return img.resize((width, h), Image.LANCZOS)


def board(columns, title, out, col_w):
    """columns: list of (heading, [images])"""
    pad, head = 40, 120
    cols = [(h, [scaled(i, col_w) for i in imgs]) for h, imgs in columns]
    height = head + max(sum(i.height + pad for i in imgs) for _, imgs in cols) + pad
    width = pad + len(cols) * (col_w + pad)
    sheet = Image.new("RGB", (width, height), BG)
    d = ImageDraw.Draw(sheet)
    d.text((pad, 24), title, fill=FG, font=font(40))
    for c, (heading, imgs) in enumerate(cols):
        x = pad + c * (col_w + pad)
        d.text((x, 78), heading, fill=(170, 170, 180), font=font(28))
        y = head
        for img in imgs:
            sheet.paste(img, (x, y))
            y += img.height + pad
    sheet.save(out, optimize=True)
    print("wrote", out)


def main(src, dst):
    src, dst = Path(src), Path(dst)
    dst.mkdir(parents=True, exist_ok=True)
    load = lambda name: Image.open(src / name).convert("RGB")
    for art in PHONE + SMALL:
        board([(name, [load(f"{d}-{mode}-{art}.png")]) for d, name, mode in DIRECTIONS],
              f"Phase 1 · {art} · three directions (primary mode)", dst / f"compare-{art}.png",
              col_w=520 if art in PHONE else 620)
    for d, name, _ in DIRECTIONS:
        cols = [(f"{art} · {mode}", [load(f"{d}-{mode}-{art}.png")]) for art in PHONE for mode in ("dark", "light")]
        board(cols[:4], f"{name} · Today and Capture", dst / f"direction-{d}-1.png", col_w=420)
        board(cols[4:], f"{name} · Meal result and Workout synced", dst / f"direction-{d}-2.png", col_w=420)
        board([(f"{art} · {mode}", [load(f"{d}-{mode}-{art}.png")]) for art in SMALL for mode in ("dark", "light")],
              f"{name} · Icon and Watch", dst / f"direction-{d}-3.png", col_w=480)
    rows = [load(f"orb-states-{d}-{m}.png") for d, _, _ in DIRECTIONS for m in ("dark", "light")]
    board([("orb states: obsidian / porcelain / aurora × dark / light", rows)], "Life Orb · states", dst / "orb-states.png", col_w=1600)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
