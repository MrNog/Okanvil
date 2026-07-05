# Okanvil — Media (dev notes)

Textures the addon draws in-game. **WoW 3.3.5a only reads `.blp`** from inside the
addon folder — it cannot load PNG/JPG at runtime, nor images from the web. So art
has to be converted to `.blp` and dropped here. (The `.png` sources are kept next to
the `.blp` for editing; only the `.blp` is actually loaded in-game.)

> This file is a dev note — it is stripped out of the release zip.

## Files the addon looks for

| file       | used by                        | referenced path                          |
|------------|--------------------------------|------------------------------------------|
| `rat1.blp` | faded blacksmith bg art (corner) | `Interface\AddOns\Okanvil\Media\rat1`   |

The code references it **without** the extension (`...\Media\rat1`) — that's correct,
WoW appends `.blp` itself. If the file is missing the texture just draws nothing
(guarded), so the UI never errors. Toggle it in **Settings → Background art → Show rat
art on pages** (`Okanvil.db.ratArt` = `"on"` / `"off"`).

## The BLP format that actually works on 3.3.5a

Hard-won: PNG, TGA, and uncompressed-BGRA BLP all FAIL on this client (diagonal-noise
corruption). What works is **BLP2 DXT5**, exactly like DBM/MRT ship:

- header: `colorEncoding = 2 (DXT)`, `alphaDepth = 8`, `alphaEncoding = 7 (DXT5)`, `hasMips = 1`
- **256×256** (power-of-two, square), full mip chain
- Verified against DBM's `Horde-Logo.blp` (same header) — matching it renders clean.

**Encoder** (no external tool): Pillow can export DDS DXT5
(`img.save(buf, format="DDS", pixel_format="DXT5")`); strip the 128-byte DDS header and
repack the raw block stream into a BLP2 with mip offsets/sizes. Pad tiny mips up to 4×4.
(The session script was `png2blp_dxt5.py`.)

## Client texture cache

3.3.5a caches textures aggressively — a `/reload` keeps the OLD (corrupt) texture. To
see a changed `.blp` you must **fully quit and relaunch WoW**, not just reload.
