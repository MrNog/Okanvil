"""Convert an image to a BLP2 DXT5 texture that WoW 3.3.5a loads.

    python scripts/png2blp_dxt5.py <in.png> <out.blp> [W[xH]] [center_y]

Matches the layout of Media/rat1.blp (known good in-game): 148-byte header,
no palette, colorEncoding 2 (DXT), alphaDepth 8, alphaEncoding 7 (DXT5),
hasMips 1, full mip chain. Sizes must be powers of two; default 512 (square).

For a non-square size (e.g. 1024x512) the source is cropped to that aspect
first, centred horizontally and at `center_y` vertically (0..1, default 0.5),
so nothing is stretched. Mips below 4px on a side are padded to a 4x4 block.
"""
import io
import struct
import sys

from PIL import Image


def dxt5(img):
    buf = io.BytesIO()
    img.save(buf, format="DDS", pixel_format="DXT5")
    return buf.getvalue()[128:]          # drop the DDS header, keep the blocks


def pow2(n):
    return n > 0 and not (n & (n - 1))


def main():
    src, dst = sys.argv[1], sys.argv[2]
    size = sys.argv[3] if len(sys.argv) > 3 else "512"
    w, h = (int(v) for v in size.split("x")) if "x" in size else (int(size), int(size))
    cy = float(sys.argv[4]) if len(sys.argv) > 4 else 0.5
    if not (pow2(w) and pow2(h)):
        sys.exit("sizes must be powers of two")

    img = Image.open(src).convert("RGBA")
    # Crop to the target aspect before scaling, so nothing gets stretched.
    sw, sh = img.size
    want = w / h
    if sw / sh > want:                   # source too wide: trim the sides
        cw, ch = int(sh * want), sh
    else:                                # source too tall: trim top/bottom
        cw, ch = sw, int(sw / want)
    x0 = (sw - cw) // 2
    y0 = int(max(0, min(sh - ch, cy * sh - ch / 2)))
    img = img.crop((x0, y0, x0 + cw, y0 + ch))

    mips, mw, mh = [], w, h
    while True:
        level = img.resize((mw, mh), Image.LANCZOS)
        if mw < 4 or mh < 4:             # DXT works on 4x4 blocks
            level = level.resize((max(4, mw), max(4, mh)), Image.LANCZOS)
        mips.append(dxt5(level))
        if mw == 1 and mh == 1:
            break
        mw, mh = max(1, mw // 2), max(1, mh // 2)
    mips = mips[:16]

    header_len = 148
    offsets, sizes, pos = [], [], header_len
    for m in mips:
        offsets.append(pos)
        sizes.append(len(m))
        pos += len(m)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))

    header = b"BLP2" + struct.pack("<I4B2I", 1, 2, 8, 7, 1, w, h)
    header += struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes)
    assert len(header) == header_len

    with open(dst, "wb") as f:
        f.write(header)
        for m in mips:
            f.write(m)
    print(f"{dst}: {w}x{h}, {len(mips)} mips, {pos} bytes")


if __name__ == "__main__":
    main()
