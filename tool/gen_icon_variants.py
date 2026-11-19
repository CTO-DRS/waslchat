"""يولّد أيقونات المشغّل البديلة (1.13.0) من أصول ic_launcher بإعادة التلوين.
الاستخدام: python3 tool/gen_icon_variants.py  (من جذر المشروع)"""
import colorsys
from PIL import Image, ImageDraw, ImageFilter

RES = 'android/app/src/main/res'
DENS = {'mdpi': (48, 108), 'hdpi': (72, 162), 'xhdpi': (96, 216), 'xxhdpi': (144, 324), 'xxxhdpi': (192, 432)}

# (الاسم، لونا الخلفية، إزاحة اللون للمقدمة بالدرجات، تشبّع، توهج الخلفية)
VARIANTS = {
    'dark':  (( 6,  8, 14), (18, 22, 34), 0, 1.0, None),
    'light': ((246, 248, 253), (222, 229, 245), 0, 1.0, None),
    'gold':  ((26, 18,  6), (58, 40, 10), -175, 1.15, (255, 196, 64)),
    'neon':  ((10,  4, 22), (40,  8, 60), 85, 1.25, (236, 72, 255)),
}


def vgrad(size, c1, c2):
    im = Image.new('RGB', (size, size))
    d = ImageDraw.Draw(im)
    for y in range(size):
        t = y / max(1, size - 1)
        d.line([(0, y), (size, y)], fill=tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)))
    return im


def recolor(fg, shift, sat):
    if shift == 0 and sat == 1.0:
        return fg.copy()
    px = fg.load()
    out = fg.copy()
    po = out.load()
    w, h = fg.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            hh = (hh + shift / 360) % 1.0
            s = min(1.0, s * sat)
            r2, g2, b2 = colorsys.hsv_to_rgb(hh, s, v)
            po[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return out


def background(size, c1, c2, glow):
    bg = vgrad(size, c1, c2).convert('RGBA')
    if glow:
        g = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(g)
        r = size * 0.32
        d.ellipse([size / 2 - r, size / 2 - r, size / 2 + r, size / 2 + r], fill=glow + (70,))
        g = g.filter(ImageFilter.GaussianBlur(size * 0.12))
        bg = Image.alpha_composite(bg, g)
    return bg


def main():
    src_fg = Image.open(f'{RES}/mipmap-xxxhdpi/ic_launcher_foreground.png').convert('RGBA')
    for name, (c1, c2, shift, sat, glow) in VARIANTS.items():
        fg_big = recolor(src_fg, shift, sat)
        bg_big = background(432, c1, c2, glow)
        for dens, (legacy, adaptive) in DENS.items():
            fg = fg_big.resize((adaptive, adaptive), Image.LANCZOS)
            bg = bg_big.resize((adaptive, adaptive), Image.LANCZOS)
            fg.save(f'{RES}/mipmap-{dens}/ic_launcher_{name}_foreground.png', optimize=True)
            bg.convert('RGB').save(f'{RES}/mipmap-{dens}/ic_launcher_{name}_background.png', optimize=True)
            # الأيقونة القديمة (قبل أندرويد 8): مربع مستدير من وسط الطبقتين
            comp = Image.alpha_composite(bg_big, fg_big)
            m = 432 * 18 // 108
            comp = comp.crop((m, m, 432 - m, 432 - m)).resize((legacy, legacy), Image.LANCZOS)
            mask = Image.new('L', (legacy * 4, legacy * 4), 0)
            ImageDraw.Draw(mask).rounded_rectangle([0, 0, legacy * 4 - 1, legacy * 4 - 1], radius=legacy * 4 * 0.22, fill=255)
            mask = mask.resize((legacy, legacy), Image.LANCZOS)
            out = Image.new('RGBA', (legacy, legacy), (0, 0, 0, 0))
            out.paste(comp, (0, 0), mask)
            out.save(f'{RES}/mipmap-{dens}/ic_launcher_{name}.png', optimize=True)
        with open(f'{RES}/mipmap-anydpi-v26/ic_launcher_{name}.xml', 'w') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                    f'    <background android:drawable="@mipmap/ic_launcher_{name}_background"/>\n'
                    f'    <foreground android:drawable="@mipmap/ic_launcher_{name}_foreground"/>\n'
                    '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
                    '</adaptive-icon>\n')
        print('ok', name)


if __name__ == '__main__':
    main()
