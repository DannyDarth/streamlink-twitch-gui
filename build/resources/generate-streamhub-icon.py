"""Generate StreamHub's diagonal purple/green Windows application icons."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ICONS = ROOT / "build" / "resources" / "icons"
ICONS.mkdir(parents=True, exist_ok=True)
SIZE = 1024
im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
# A rounded-square purple/green split, with the split crossing diagonally.
mask = Image.new("L", (SIZE, SIZE), 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle((35, 35, 989, 989), radius=190, fill=255)
purple = Image.new("RGBA", (SIZE, SIZE), "#9146ff")
green = Image.new("RGBA", (SIZE, SIZE), "#53fc18")
split = Image.new("L", (SIZE, SIZE), 0)
sd = ImageDraw.Draw(split)
sd.polygon([(1024, 0), (1024, 1024), (0, 1024)], fill=255)
purple.paste(green, (0, 0), split)
im.paste(purple, (0, 0), mask)
d = ImageDraw.Draw(im)
# White TV and play glyph.
d.rounded_rectangle((190, 275, 834, 716), radius=105, fill="white")
d.rounded_rectangle((248, 333, 776, 657), radius=66, fill="#6725a8")
# Reintroduce diagonal color split inside the screen.
d.polygon([(776, 333), (776, 657), (452, 657)], fill="#32cc12")
d.polygon([(430, 420), (430, 575), (583, 497)], fill="white")
d.line([(425, 275), (350, 200)], fill="white", width=45)
d.line([(599, 275), (674, 200)], fill="white", width=45)
# StreamHub lettering sized to remain visible at desktop icon resolutions.
fonts = [
    Path("C:/Windows/Fonts/arialbd.ttf"),
    Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
]
font_path = next((p for p in fonts if p.exists()), None)
font = ImageFont.truetype(str(font_path), 106) if font_path else ImageFont.load_default()
d.text((SIZE // 2, 815), "StreamHub", font=font, anchor="mm",
       fill="white", stroke_width=5, stroke_fill="#24142e")
# Prefer the user-supplied StreamHub artwork when present in the repository.
# Keep the legacy generated icon as a fallback until the new PNG is uploaded.
custom_icon = ROOT / "build" / "resources" / "streamhub-custom-icon.png"
if custom_icon.is_file():
    im = Image.open(custom_icon).convert("RGBA").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
im.save(ICONS / "streamhub-1024.png")
im.save(ICONS / "icon-16-32-48-256.ico", format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
im.resize((256, 256), Image.Resampling.LANCZOS).save(ICONS / "streamhub-256.png")
# NW.js loads this asset for the application window and running taskbar button.
RUNTIME = ROOT / "src" / "app" / "assets" / "icons"
RUNTIME.mkdir(parents=True, exist_ok=True)
im.resize((256, 256), Image.Resampling.LANCZOS).save(RUNTIME / "icon-256.png")

# NSIS Modern UI welcome/finish sidebar: branded artwork based on the icon.
# NSIS expects a 24-bit BMP, 164 x 314 pixels.
sidebar = Image.new("RGB", (164, 314), "#151321")
side = ImageDraw.Draw(sidebar)
side.polygon([(0, 0), (164, 0), (0, 260)], fill="#7829ce")
side.polygon([(164, 45), (164, 314), (0, 314)], fill="#38c914")
side.polygon([(0, 220), (164, 0), (164, 45), (0, 265)], fill="#24142e")
logo = im.copy()
logo.thumbnail((140, 140), Image.Resampling.LANCZOS)
sidebar.paste(logo, ((164 - logo.width) // 2, 75), logo)
side.text((82, 248), "StreamHub", anchor="mm", fill="white", font=ImageFont.truetype(str(font_path), 20) if font_path else ImageFont.load_default())
sidebar.save(ICONS / "streamhub-installer-sidebar.bmp", format="BMP")
