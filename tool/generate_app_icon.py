"""Render the app icon's SVG to its checked-in launcher resources.

Run with Python, Pillow and PyMuPDF. Flutter builds use the rendered files.
"""
from decimal import Decimal
import json
from pathlib import Path

import fitz
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/icon/quill-clock.svg'


def save_png(icon, path, size):
    icon.resize(size, Image.Resampling.LANCZOS).save(path, optimize=True)


def save_apple_icons(platform, icon):
    catalog = ROOT / platform / 'Runner/Assets.xcassets/AppIcon.appiconset'
    entries = json.loads((catalog / 'Contents.json').read_text(encoding='utf-8'))['images']
    for entry in entries:
        scale = int(entry['scale'].removesuffix('x'))
        size = tuple(int(Decimal(edge) * scale) for edge in entry['size'].split('x'))
        save_png(icon, catalog / entry['filename'], size)


def main():
    svg = SOURCE.read_text(encoding='utf-8-sig').encode('utf-8')
    with fitz.open(stream=svg, filetype='svg') as document:
        pixmap = document[0].get_pixmap(matrix=fitz.Matrix(2, 2), alpha=True)
        icon = Image.frombytes('RGBa', (pixmap.width, pixmap.height), pixmap.samples).convert('RGBA')
    icon.save(ROOT / 'assets/icon/ICON.png', optimize=True)
    (ROOT / 'docs/quill-clock.svg').write_bytes(svg)
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        path = ROOT / f'android/app/src/main/res/mipmap-{density}/launcher_icon.png'
        save_png(icon, path, (size, size))
    windows_sizes = [(n, n) for n in [16, 20, 24, 32, 40, 48, 64, 128, 256]]
    icon.save(ROOT / 'windows/runner/resources/app_icon.ico', sizes=windows_sizes)

    # The clock face fits inside the circular safe area. Use the background
    # colour to fill the corners for masked launchers and Apple's iOS icons.
    opaque = Image.new('RGB', icon.size, '#211D24')
    opaque.paste(icon, mask=icon.getchannel('A'))
    save_png(icon, ROOT / 'web/favicon.png', (32, 32))
    for size in (192, 512):
        save_png(icon, ROOT / f'web/icons/Icon-{size}.png', (size, size))
        save_png(opaque, ROOT / f'web/icons/Icon-maskable-{size}.png', (size, size))

    save_apple_icons('ios', opaque)
    save_apple_icons('macos', icon)


if __name__ == '__main__':
    main()
