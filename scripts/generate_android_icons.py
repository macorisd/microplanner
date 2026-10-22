"""Generate Android resources from the existing Windows-matching artwork.

Run with Python and Pillow: python scripts/generate_android_icons.py
"""
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'android/app/src/main/res'
source = Image.open(ROOT / 'assets/images/microplanner_logo.png').convert('RGBA')


def icon(size, artwork_size, background):
    result = Image.new('RGBA', (size, size), background)
    artwork = ImageOps.contain(source, (artwork_size, artwork_size), Image.Resampling.LANCZOS)
    result.alpha_composite(artwork, ((size - artwork.width) // 2, (size - artwork.height) // 2))
    return result


for density, factor in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]:
    directory = RES / f'mipmap-{density}'
    directory.mkdir(exist_ok=True)
    icon(round(48 * factor), round(48 * factor), (0, 0, 0, 0)).save(directory / 'ic_launcher.png')
    # Fill the launcher's 72dp viewport, preserving the source transparency.
    icon(round(108 * factor), round(72 * factor), (0, 0, 0, 0)).save(directory / 'ic_launcher_foreground.png')

adaptive = RES / 'mipmap-anydpi-v26'
adaptive.mkdir(exist_ok=True)
(adaptive / 'ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''', encoding='utf-8')
(RES / 'values/launcher_colors.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="launcher_background">#00000000</color>
</resources>
''', encoding='utf-8')
