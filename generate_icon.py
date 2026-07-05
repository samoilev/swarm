#!/usr/bin/env python3
"""Generate a macOS app icon (.icns) for FamilyTreeStudio."""
from PIL import Image, ImageDraw, ImageFont
import subprocess, os, tempfile, math

SIZE = 1024

def draw_icon():
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Background: rounded square with sepia gradient feel
    bg_color = (245, 237, 220, 255)  # warm cream
    border_color = (160, 120, 80, 255)  # sepia border
    
    # Draw rounded rectangle background
    radius = 180
    draw.rounded_rectangle([40, 40, SIZE-40, SIZE-40], radius=radius, fill=bg_color, outline=border_color, width=8)
    
    # Inner subtle border
    draw.rounded_rectangle([60, 60, SIZE-60, SIZE-60], radius=radius-15, outline=(190, 155, 110, 100), width=3)
    
    # Tree trunk and branches - elegant stylized tree
    trunk_color = (110, 70, 40, 255)  # dark brown
    branch_color = (130, 85, 50, 255)  # medium brown
    leaf_color = (85, 120, 60, 200)  # muted sage green
    
    cx, cy = SIZE // 2, SIZE // 2 + 40
    
    # Trunk
    trunk_pts = [
        (cx - 28, cy + 200),
        (cx + 28, cy + 200),
        (cx + 20, cy + 40),
        (cx - 20, cy + 40),
    ]
    draw.polygon(trunk_pts, fill=trunk_color)
    
    # Roots (subtle)
    for angle in [-40, -20, 0, 20, 40]:
        rad = math.radians(angle)
        x1 = cx + int(18 * math.sin(rad))
        y1 = cy + 195
        x2 = cx + int(55 * math.sin(rad))
        y2 = cy + 220 + abs(angle) // 3
        draw.line([(x1, y1), (x2, y2)], fill=trunk_color, width=6)
    
    # Main branches
    branches = [
        # (start_offset_x, start_y_offset, end_x, end_y, width)
        (0, 40, -160, -120, 14),
        (0, 40, 160, -120, 14),
        (-10, 10, -240, -60, 10),
        (10, 10, 240, -60, 10),
        (0, 60, -100, -20, 10),
        (0, 60, 100, -20, 10),
        # Upper branches
        (-160, -120, -250, -200, 8),
        (-160, -120, -100, -220, 8),
        (160, -120, 250, -200, 8),
        (160, -120, 100, -220, 8),
        (0, 40, 0, -180, 12),
        (0, -180, -60, -260, 7),
        (0, -180, 60, -260, 7),
    ]
    
    for sx, sy, ex, ey, w in branches:
        draw.line([(cx+sx, cy+sy), (cx+ex, cy+ey)], fill=branch_color, width=w)
    
    # Circles at branch ends representing family members
    circle_positions = [
        # (x_offset, y_offset, size, generation_color)
        (0, -280, 52, (139, 90, 43, 255)),     # top center - oldest
        (-60, -280, 44, (139, 90, 43, 255)),
        (60, -280, 44, (139, 90, 43, 255)),
        (-250, -210, 44, (160, 110, 60, 255)),
        (-100, -230, 44, (160, 110, 60, 255)),
        (100, -230, 44, (160, 110, 60, 255)),
        (250, -210, 44, (160, 110, 60, 255)),
        (-240, -70, 40, (180, 130, 75, 255)),
        (-100, -30, 40, (180, 130, 75, 255)),
        (100, -30, 40, (180, 130, 75, 255)),
        (240, -70, 40, (180, 130, 75, 255)),
    ]
    
    for ox, oy, sz, color in circle_positions:
        x, y = cx + ox, cy + oy
        # Shadow
        draw.ellipse([x-sz//2+3, y-sz//2+3, x+sz//2+3, y+sz//2+3], fill=(0, 0, 0, 30))
        # Circle
        draw.ellipse([x-sz//2, y-sz//2, x+sz//2, y+sz//2], fill=color, outline=(90, 55, 25, 200), width=3)
        # Inner highlight
        draw.ellipse([x-sz//4, y-sz//4-4, x+sz//6, y-sz//6-4], fill=(255, 255, 255, 40))
    
    # Connecting lines between circles (family connections)
    conn_color = (110, 70, 40, 120)
    connections = [
        (0, -280, -60, -280),
        (0, -280, 60, -280),
        (-250, -210, -100, -230),
        (100, -230, 250, -210),
    ]
    for sx, sy, ex, ey in connections:
        draw.line([(cx+sx, cy+sy), (cx+ex, cy+ey)], fill=conn_color, width=3)
    
    # Bottom text area - app name initial
    # Small decorative element at bottom
    draw.arc([cx-80, cy+230, cx+80, cy+290], 0, 180, fill=(160, 120, 80, 150), width=3)
    
    return img


def create_icns(img, output_path):
    """Create .icns from a PIL image."""
    tmpdir = tempfile.mkdtemp()
    iconset_path = os.path.join(tmpdir, "AppIcon.iconset")
    os.makedirs(iconset_path)
    
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for size in sizes:
        resized = img.resize((size, size), Image.LANCZOS)
        resized.save(os.path.join(iconset_path, f"icon_{size}x{size}.png"))
        if size <= 512:
            resized2x = img.resize((size*2, size*2), Image.LANCZOS)
            resized2x.save(os.path.join(iconset_path, f"icon_{size}x{size}@2x.png"))
    
    subprocess.run(["iconutil", "-c", "icns", iconset_path, "-o", output_path], check=True)
    # Cleanup
    import shutil
    shutil.rmtree(tmpdir)
    print(f"Created: {output_path}")


if __name__ == "__main__":
    icon = draw_icon()
    output = os.path.join(os.path.dirname(__file__), "FamilyTreeStudio", "Resources", "AppIcon.icns")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    create_icns(icon, output)
    # Also save a preview PNG
    icon.save(os.path.join(os.path.dirname(output), "AppIcon_preview.png"))
    print("Done!")
