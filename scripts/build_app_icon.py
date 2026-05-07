from math import cos, radians, sin
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "assets" / "AppIcon.iconset"
ICNS = ROOT / "assets" / "AppIcon.icns"
PREVIEW = ROOT / "assets" / "AppIcon-preview.png"

SIZES = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


def vertical_gradient(size, top, bottom):
    image = Image.new("RGBA", (size, size), top)
    pixels = image.load()
    for y in range(size):
        t = y / max(1, size - 1)
        row = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(4))
        for x in range(size):
            pixels[x, y] = row
    return image


def radial_gradient(size, inner, outer):
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()
    cx = cy = size / 2
    radius = size / 2
    for y in range(size):
        for x in range(size):
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            t = min((dx * dx + dy * dy) ** 0.5 / radius, 1)
            pixels[x, y] = tuple(int(inner[i] * (1 - t) + outer[i] * t) for i in range(4))
    return image


def rounded_mask(size, box, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(box, radius=radius, fill=255)
    return mask


def ellipse_mask(size, box):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse(box, fill=255)
    return mask


def paste_with_mask(base, fill, mask, offset=(0, 0)):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.paste(fill, offset)
    base.alpha_composite(layer, (0, 0), mask)


def point_on_arc(box, angle):
    cx = (box[0] + box[2]) / 2
    cy = (box[1] + box[3]) / 2
    rx = (box[2] - box[0]) / 2
    ry = (box[3] - box[1]) / 2
    theta = radians(angle)
    return cx + cos(theta) * rx, cy + sin(theta) * ry


def make_master(size=1024):
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    tile_box = (
        int(size * 0.16),
        int(size * 0.12),
        int(size * 0.84),
        int(size * 0.88),
    )
    tile_width = tile_box[2] - tile_box[0]
    radius = int(tile_width * 0.24)

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle(
        (
            tile_box[0],
            tile_box[1] + int(size * 0.028),
            tile_box[2],
            tile_box[3] + int(size * 0.028),
        ),
        radius=radius,
        fill=(22, 36, 60, 58),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(size * 0.028)))
    canvas.alpha_composite(shadow)

    tile_fill = vertical_gradient(size, (249, 251, 255, 255), (232, 238, 248, 255))
    tile_mask = rounded_mask(size, tile_box, radius)
    tile_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tile_layer.paste(tile_fill, (0, 0), tile_mask)
    canvas.alpha_composite(tile_layer)

    inner_glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(inner_glow)
    inset = int(size * 0.018)
    gdraw.rounded_rectangle(
        (
            tile_box[0] + inset,
            tile_box[1] + inset,
            tile_box[2] - inset,
            tile_box[3] - inset,
        ),
        radius=radius - inset,
        outline=(255, 255, 255, 180),
        width=max(5, size // 110),
    )
    inner_glow = inner_glow.filter(ImageFilter.GaussianBlur(int(size * 0.004)))
    canvas.alpha_composite(inner_glow)

    stroke = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    st_draw = ImageDraw.Draw(stroke)
    st_draw.rounded_rectangle(
        tile_box,
        radius=radius,
        outline=(196, 208, 226, 255),
        width=max(7, size // 66),
    )
    canvas.alpha_composite(stroke)

    shine = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(shine)
    shine_box = (
        tile_box[0] + int(tile_width * 0.08),
        tile_box[1] + int(tile_width * 0.06),
        tile_box[2] - int(tile_width * 0.16),
        tile_box[1] + int(tile_width * 0.34),
    )
    sh_draw.rounded_rectangle(shine_box, radius=int(tile_width * 0.14), fill=(255, 255, 255, 78))
    shine = shine.filter(ImageFilter.GaussianBlur(int(size * 0.018)))
    canvas.alpha_composite(shine)

    core_size = int(size * 0.34)
    core_cx = int(size * 0.49)
    core_cy = int(size * 0.48)
    core_box = (
        core_cx - core_size // 2,
        core_cy - core_size // 2,
        core_cx + core_size // 2,
        core_cy + core_size // 2,
    )

    core_shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cs_draw = ImageDraw.Draw(core_shadow)
    cs_draw.ellipse(
        (
            core_box[0],
            core_box[1] + int(size * 0.015),
            core_box[2],
            core_box[3] + int(size * 0.015),
        ),
        fill=(15, 24, 43, 80),
    )
    core_shadow = core_shadow.filter(ImageFilter.GaussianBlur(int(size * 0.02)))
    canvas.alpha_composite(core_shadow)

    core_grad = radial_gradient(core_size, (94, 120, 196, 255), (24, 33, 61, 255))
    core_alpha = Image.new("L", (core_size, core_size), 0)
    ImageDraw.Draw(core_alpha).ellipse((0, 0, core_size, core_size), fill=255)
    core_grad.putalpha(core_alpha)
    core_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    core_layer.paste(core_grad, (core_box[0], core_box[1]), core_grad)
    canvas.alpha_composite(core_layer)

    core_rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cr_draw = ImageDraw.Draw(core_rim)
    cr_draw.ellipse(core_box, outline=(230, 240, 255, 215), width=max(8, size // 82))
    canvas.alpha_composite(core_rim)

    core_sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    csh_draw = ImageDraw.Draw(core_sheen)
    csh_draw.ellipse(
        (
            core_box[0] + int(core_size * 0.14),
            core_box[1] + int(core_size * 0.10),
            core_box[0] + int(core_size * 0.52),
            core_box[1] + int(core_size * 0.42),
        ),
        fill=(255, 255, 255, 90),
    )
    core_sheen = core_sheen.filter(ImageFilter.GaussianBlur(int(size * 0.01)))
    canvas.alpha_composite(core_sheen)

    orbit_box = (
        core_box[0] - int(size * 0.055),
        core_box[1] - int(size * 0.045),
        core_box[2] + int(size * 0.055),
        core_box[3] + int(size * 0.055),
    )
    orbit_width = max(10, size // 42)

    orbit_glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    og_draw = ImageDraw.Draw(orbit_glow)
    og_draw.arc(orbit_box, start=210, end=18, fill=(111, 192, 255, 120), width=orbit_width + max(6, size // 120))
    orbit_glow = orbit_glow.filter(ImageFilter.GaussianBlur(int(size * 0.01)))
    canvas.alpha_composite(orbit_glow)

    orbit = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    o_draw = ImageDraw.Draw(orbit)
    o_draw.arc(orbit_box, start=210, end=18, fill=(126, 206, 255, 235), width=orbit_width)
    o_draw.arc(orbit_box, start=228, end=280, fill=(255, 255, 255, 150), width=max(4, orbit_width // 3))
    canvas.alpha_composite(orbit)

    dot_size = int(size * 0.13)
    dot_cx, dot_cy = point_on_arc(orbit_box, 28)
    dot_box = (
        int(dot_cx - dot_size / 2),
        int(dot_cy - dot_size / 2),
        int(dot_cx + dot_size / 2),
        int(dot_cy + dot_size / 2),
    )

    dot_shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ds_draw = ImageDraw.Draw(dot_shadow)
    ds_draw.ellipse(
        (
            dot_box[0],
            dot_box[1] + int(size * 0.01),
            dot_box[2],
            dot_box[3] + int(size * 0.01),
        ),
        fill=(10, 75, 56, 72),
    )
    dot_shadow = dot_shadow.filter(ImageFilter.GaussianBlur(int(size * 0.012)))
    canvas.alpha_composite(dot_shadow)

    dot_grad = radial_gradient(dot_size, (120, 244, 206, 255), (34, 176, 120, 255))
    dot_alpha = Image.new("L", (dot_size, dot_size), 0)
    ImageDraw.Draw(dot_alpha).ellipse((0, 0, dot_size, dot_size), fill=255)
    dot_grad.putalpha(dot_alpha)
    dot_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dot_layer.paste(dot_grad, (dot_box[0], dot_box[1]), dot_grad)
    canvas.alpha_composite(dot_layer)

    dot_rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dr_draw = ImageDraw.Draw(dot_rim)
    dr_draw.ellipse(dot_box, outline=(243, 255, 250, 255), width=max(5, size // 120))
    canvas.alpha_composite(dot_rim)

    return canvas


def main():
    ICONSET.mkdir(parents=True, exist_ok=True)
    master = make_master(1024)
    master.save(PREVIEW)
    for size, filename in SIZES:
        master.resize((size, size), Image.LANCZOS).save(ICONSET / filename)
    if ICNS.exists():
        ICNS.unlink()
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(ICNS)
    print(PREVIEW)


if __name__ == "__main__":
    main()
