#!/usr/bin/env python3
"""Tile the A2 poster onto 2×A3 or 4×A4 sheets that glue into one poster."""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import generate as g

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ROOT = g.ROOT
DPI = 192

# A2 landscape at 96 CSS px/in, captured at 2× → 192 dpi
A2_W_PX = 2245
A2_H_PX = 1588


def export_html() -> Path:
    html = g.build_html(g.json.loads(g.DATA.read_text(encoding="utf-8")))
    html = html.replace("<body>", '<body class="export">', 1)
    extra = """
  body.export { background: #eef6fb; }
  body.export .toolbar { display: none !important; }
  body.export .stage { padding: 0; }
  body.export .sheet { transform: none !important; }
"""
    html = html.replace("body {", extra + "\n  body {", 1)
    out = ROOT / "_export-a2.html"
    out.write_text(html, encoding="utf-8")
    return out


def capture_a2(html_path: Path, png_path: Path) -> None:
    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--force-device-scale-factor=2",
            f"--window-size={A2_W_PX},{A2_H_PX}",
            f"--screenshot={png_path}",
            html_path.as_uri(),
        ],
        check=True,
        capture_output=True,
    )


def font(size: int) -> ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ):
        p = Path(path)
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def mini_map(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], cells: list[bool], cols: int) -> None:
    x, y, w, h = box
    rows = (len(cells) + cols - 1) // cols
    gap = 2
    cw = (w - gap * (cols - 1)) // cols
    ch = (h - gap * (rows - 1)) // rows
    for i, on in enumerate(cells):
        c, r = i % cols, i // cols
        rx = x + c * (cw + gap)
        ry = y + r * (ch + gap)
        fill = (0, 48, 130) if on else (220, 232, 242)
        draw.rectangle((rx, ry, rx + cw, ry + ch), fill=fill, outline=(0, 48, 130), width=1)


def mark_tile(im: Image.Image, index: int, total: int, corner: str, cells: list[bool], cols: int) -> Image.Image:
    """Label only the outer corner so the seam stays clean."""
    im = im.convert("RGB")
    draw = ImageDraw.Draw(im)
    label = f"{index}/{total}"
    fnt = font(22)
    pad = 14
    tw, th = draw.textbbox((0, 0), label, font=fnt)[2:]
    map_w, map_h = 36 if cols == 2 and total == 2 else 40, 22 if total == 2 else 40
    block_w = max(tw, map_w) + 16
    block_h = th + map_h + 18
    if corner == "tl":
        x, y = pad, pad
    elif corner == "tr":
        x, y = im.width - block_w - pad, pad
    elif corner == "bl":
        x, y = pad, im.height - block_h - pad
    else:
        x, y = im.width - block_w - pad, im.height - block_h - pad
    draw.rectangle((x, y, x + block_w, y + block_h), fill=(255, 255, 255), outline=(0, 151, 219), width=2)
    draw.text((x + 8, y + 4), label, fill=(0, 48, 130), font=fnt)
    mini_map(draw, (x + 8, y + th + 8, map_w, map_h), cells, cols)
    return im


def save_pdf(pages: list[Image.Image], out: Path) -> None:
    rgb = [p.convert("RGB") for p in pages]
    rgb[0].save(out, save_all=True, append_images=rgb[1:], resolution=float(DPI))
    w_mm = rgb[0].width / DPI * 25.4
    h_mm = rgb[0].height / DPI * 25.4
    print(f"wrote {out.name}: {len(rgb)} стр. · {w_mm:.0f}×{h_mm:.0f} мм")


def main() -> None:
    g.main()
    html_path = export_html()
    with tempfile.TemporaryDirectory() as tmp:
        full = Path(tmp) / "a2.png"
        print("снимаю A2-постер…")
        capture_a2(html_path, full)
        poster = Image.open(full)
        w, h = poster.size
        print(f"  снимок {w}×{h}px")
        save_pdf([poster.convert("RGB")], ROOT / "rpl-2026-27.pdf")

        mid_x = w // 2
        mid_y = h // 2

        left = poster.crop((0, 0, mid_x, h))
        right = poster.crop((mid_x, 0, w, h))
        two = [
            mark_tile(left, 1, 2, "bl", [True, False], 2),
            mark_tile(right, 2, 2, "br", [False, True], 2),
        ]
        save_pdf(two, ROOT / "rpl-2026-27-2lista.pdf")

        tiles = [
            (poster.crop((0, 0, mid_x, mid_y)), 1, "tl", [True, False, False, False]),
            (poster.crop((mid_x, 0, w, mid_y)), 2, "tr", [False, True, False, False]),
            (poster.crop((0, mid_y, mid_x, h)), 3, "bl", [False, False, True, False]),
            (poster.crop((mid_x, mid_y, w, h)), 4, "br", [False, False, False, True]),
        ]
        four = [mark_tile(im, n, 4, corner, cells, 2) for im, n, corner, cells in tiles]
        save_pdf(four, ROOT / "rpl-2026-27-4lista.pdf")

    html_path.unlink(missing_ok=True)
    for extra in (ROOT / "rpl-2026-27-2lista.html", ROOT / "rpl-2026-27-4lista.html"):
        extra.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
