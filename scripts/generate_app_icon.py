#!/usr/bin/env python3
"""
Stub summary for /Users/stuart/parallel_development/uff_dev/mar23_pm_1_ios_build_icon_testflight/uff_dev/scripts/generate_app_icon.py.
"""

import json
from decimal import Decimal
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# Project root is one level up from scripts/
PROJECT_ROOT = Path(__file__).resolve().parent.parent
IOS_APPICONSET_DIR = PROJECT_ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
ANDROID_RES_DIR = PROJECT_ROOT / "android" / "app" / "src" / "main" / "res"

# Brand colors
BG_COLOR = (26, 26, 46)  # dark navy/charcoal
TEXT_COLOR = (255, 255, 255)  # white

# Font config
FONT_PATH = "/System/Library/Fonts/Helvetica.ttc"
BASE_SIZE = 1024

# Android icons: mipmap density -> pixel size
ANDROID_ICONS = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def render_base_icon() -> Image.Image:
    """Render the 1024x1024 base icon with "Uff" wordmark centered."""
    img = Image.new("RGB", (BASE_SIZE, BASE_SIZE), BG_COLOR)
    draw = ImageDraw.Draw(img)

    # Use a large font size relative to the canvas — tuned so "Uff" fills
    # roughly 60% of the width for good legibility at small sizes.
    font_size = int(BASE_SIZE * 0.38)
    font = ImageFont.truetype(FONT_PATH, font_size)

    text = "Uff"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]

    # Center the text on the canvas, adjusting for the bbox offset
    x = (BASE_SIZE - text_width) / 2 - bbox[0]
    y = (BASE_SIZE - text_height) / 2 - bbox[1]

    draw.text((x, y), text, fill=TEXT_COLOR, font=font)
    return img


def ios_pixel_size(image: dict[str, str]) -> int:
    """Convert an iOS Contents.json image entry into a square pixel size."""
    point_size = Decimal(image["size"].split("x", maxsplit=1)[0])
    scale = Decimal(image["scale"].removesuffix("x"))
    return int(point_size * scale)


def load_ios_icons() -> dict[str, int]:
    """TODO: Document load_ios_icons."""
    contents = json.loads((IOS_APPICONSET_DIR / "Contents.json").read_text())
    icons: dict[str, int] = {}
    for image in contents["images"]:
        filename = image.get("filename")
        if not filename:
            continue
        pixel_size = ios_pixel_size(image)
        existing_size = icons.get(filename)
        if existing_size is not None and existing_size != pixel_size:
            raise ValueError(
                f"Conflicting pixel sizes for {filename}: {existing_size} vs {pixel_size}"
            )
        icons[filename] = pixel_size
    return icons


def write_resized_icon(base: Image.Image, size: int, output_path: Path, label: str) -> None:
    """Resize the base icon, save it as PNG, and print a readable status line."""
    resized = base.resize((size, size), Image.LANCZOS)
    resized.save(output_path, "PNG")
    print(f"  {label} ({size}x{size})")


def write_ios_icons(base: Image.Image) -> None:
    """Resize and write all 15 iOS icon PNGs."""
    for filename, size in load_ios_icons().items():
        write_resized_icon(base, size, IOS_APPICONSET_DIR / filename, f"iOS: {filename}")


def write_android_icons(base: Image.Image) -> None:
    """Resize and write all 5 Android mipmap ic_launcher PNGs."""
    for density, size in ANDROID_ICONS.items():
        output_path = ANDROID_RES_DIR / f"mipmap-{density}" / "ic_launcher.png"
        write_resized_icon(
            base,
            size,
            output_path,
            f"Android: mipmap-{density}/ic_launcher.png",
        )


def main() -> None:
    print("Generating Uff brand icon (1024x1024 base)...")
    base = render_base_icon()

    print("Writing iOS icons...")
    write_ios_icons(base)

    print("Writing Android icons...")
    write_android_icons(base)

    print("Done. All icons generated.")


if __name__ == "__main__":
    main()
