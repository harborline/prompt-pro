#!/usr/bin/env python3
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


CANVAS_SIZE = (1440, 900)
BACKGROUND = "#2E3440"
PANEL = "#3B4252"
ACCENT = "#88C0D0"


def render(source_path: Path, output_path: Path, title: str) -> None:
    source = Image.open(source_path).convert("RGBA")
    canvas = Image.new("RGB", CANVAS_SIZE, BACKGROUND)
    draw = ImageDraw.Draw(canvas)

    draw.rectangle((0, 0, CANVAS_SIZE[0], 108), fill=PANEL)
    draw.rectangle((0, 106, CANVAS_SIZE[0], 110), fill=ACCENT)
    draw.text((56, 38), title, fill="#ECEFF4")

    max_width = 1260
    max_height = 680
    scale = min(max_width / source.width, max_height / source.height, 1.35)
    rendered_size = (round(source.width * scale), round(source.height * scale))
    source = source.resize(rendered_size, Image.Resampling.LANCZOS)

    x = (CANVAS_SIZE[0] - source.width) // 2
    y = 150 + (max_height - source.height) // 2
    shadow = Image.new("RGBA", source.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (0, 0, source.width, source.height),
        radius=38,
        fill=(0, 0, 0, 170),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    canvas.paste(shadow, (x + 0, y + 18), shadow)
    canvas.paste(source, (x, y), source)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path)


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: render_app_store_screenshot.py <source> <output> <title>", file=sys.stderr)
        return 2

    render(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
