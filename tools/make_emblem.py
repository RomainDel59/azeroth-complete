"""Converts the emblem artwork (art/emblem.png, a medallion on a white background) into the
texture the addon loads: AzerothComplete/Media/Emblem.tga, 256 x 256, 32-bit with alpha.

The white background becomes transparent through a circular mask fitted to the medallion,
with an antialiased edge. Usage: python -I tools/make_emblem.py
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "art" / "emblem.png"
TARGET = ROOT / "AzerothComplete" / "Media" / "Emblem.tga"
SIZE = 256
SUPERSAMPLE = 4
WHITE_TOLERANCE = 24


def main() -> None:
    image = Image.open(SOURCE).convert("RGB")
    # Bounding box of everything that is not (nearly) white: the medallion.
    difference = ImageChops.difference(image, Image.new("RGB", image.size, (255, 255, 255)))
    mask = difference.convert("L").point(lambda value: 255 if value > WHITE_TOLERANCE else 0)
    left, top, right, bottom = mask.getbbox()
    side = max(right - left, bottom - top)
    center_x, center_y = (left + right) / 2, (top + bottom) / 2
    box = (int(center_x - side / 2), int(center_y - side / 2), int(center_x + side / 2), int(center_y + side / 2))
    medallion = image.crop(box).resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")

    # Antialiased circular alpha, drawn larger then reduced.
    big = SIZE * SUPERSAMPLE
    circle = Image.new("L", (big, big), 0)
    ImageDraw.Draw(circle).ellipse((2, 2, big - 3, big - 3), fill=255)
    medallion.putalpha(circle.resize((SIZE, SIZE), Image.LANCZOS))

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    medallion.save(TARGET, format="TGA", compression=None)
    print(f"wrote {TARGET.relative_to(ROOT)} ({SIZE}x{SIZE}, from {SOURCE.name} box {box})")


if __name__ == "__main__":
    main()
