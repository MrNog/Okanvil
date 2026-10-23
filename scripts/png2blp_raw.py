"""PNG -> BLP2, uncompressed BGRA, no mipmaps.

The format of Blizzard's own small UI art (redbutton2x.blp): every pixel kept
as drawn. DXT5 (png2blp_dxt5.py) is right for big art like the window
backgrounds, but on a 36px button it smears the edges and the mipmaps blur it
further, so a small control saved that way looks soft next to the X.

    python png2blp_raw.py in.png out.blp

The image must be a power of two on each side (128x64 is fine).
"""
import struct
import sys

from PIL import Image


def main(src, dst):
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    for n in (w, h):
        if n & (n - 1):
            sys.exit(f"{src}: {w}x{h} is not a power of two on each side")
    r, g, b, a = im.split()
    data = Image.merge("RGBA", (b, g, r, a)).tobytes()  # BGRA, row by row

    header = struct.pack("<4sIBBBBII", b"BLP2", 1, 3, 8, 8, 0, w, h)
    offsets = [148 + 1024] + [0] * 15
    sizes = [len(data)] + [0] * 15
    header += struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes)
    palette = b"\0" * 1024  # present in the header block, unused by BGRA
    with open(dst, "wb") as f:
        f.write(header + palette + data)
    print(f"{dst}: {w}x{h} BGRA, {len(header) + len(palette) + len(data)} bytes")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
