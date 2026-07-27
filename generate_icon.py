#!/usr/bin/env python3
"""Build Swarm's macOS .icns from the committed supplied artwork."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "Swarm/App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
OUTPUT = ROOT / "Swarm/App/Resources/AppIcon.icns"
ICNS_SIZES = [
    (16, 16),
    (32, 32),
    (64, 64),
    (128, 128),
    (256, 256),
    (512, 512),
    (1024, 1024),
]


def main() -> None:
    icon = Image.open(SOURCE).convert("RGBA")
    if icon.size != (1024, 1024):
        raise ValueError(f"Expected a 1024×1024 source icon, found {icon.size}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUTPUT, format="ICNS", sizes=ICNS_SIZES)
    print(f"Created: {OUTPUT}")


if __name__ == "__main__":
    main()
