# TheDraw Font (.TDF) File Format Specification

> Source: Roy/SAC, "TheDraw Fonts File (.TDF) Specifications", 2014-04-23,
> https://www.roysac.com/blog/2014/04/thedraw-fonts-file-tdf-specifications/

This is a reverse-engineered specification of the .TDF binary container used by TheDraw (an MS-DOS ANSI/ASCII text editor) for its fonts. It is not an official Apple-style spec — it was deduced empirically by Roy/SAC by inspecting actual font files and the TDFONTS.EXE editor's output. SwiftTDF treats this document as authoritative.

## File container

A .TDF file is a **collection** of up to **34 fonts**. An empty file is exactly **232 bytes**: a 20-byte file header followed by a 212-byte placeholder font header. Character data starts at offset 233 in single-font files.

Files are little-endian throughout.

### File header (offsets 0..19, fixed 20 bytes)

| Offset | Length | Value | Notes |
|---|---|---|---|
| 0 | 1 | `0x13` | Magic. |
| 1 | 18 | `"TheDraw FONTS file"` | ASCII signature. |
| 19 | 1 | `0x1A` | CP/M EOF marker. |

## Per-font header (212 bytes, repeated per font in the collection)

The first font's header begins at offset 20.

| Offset (relative) | Length | Description |
|---|---|---|
| 0 | 4 | `0x55 0xAA 0x00 0xFF` — start-of-font sentinel. |
| 4 | 1 | Font name length `L` (`1..12`). |
| 5 | 12 | Font name string; only first `L` bytes are meaningful, the rest may be NUL or garbage. |
| 17 | 4 | Reserved; observed as zero. |
| 21 | 1 | Font type — `0x00` outline, `0x01` block, `0x02` color. |
| 22 | 1 | Letter spacing, `0x01..0x29` decimal-equivalent `0..40`. |
| 23 | 2 | Block size (LE `UInt16`) — size in bytes of the character-data block that follows. |
| 25 | 188 | 94 × 2-byte LE offsets, one per glyph for ASCII `'!'` (33) through `'~'` (126). `0xFFFF` means "glyph undefined". Any other value is an offset (from 0) into the character-data block where this glyph's data begins. |

### Subsequent fonts in a collection

| Position | Computation |
|---|---|
| Font 1 header | offset 20 |
| Font 1 data | offset 233 |
| Font 2 header | (font 1 data end + 1 separator byte) |
| Font 2 data | (font 2 header + 213 bytes) |
| Font N data end | char data block end |

Fonts in the collection are NUL-separated EXCEPT the last font, which is NOT NUL-terminated.

## Character data

Each glyph entry begins with two header bytes:

| Offset | Length | Description |
|---|---|---|
| 0 | 1 | Max width, `1..30` (`0x1E`). |
| 1 | 1 | Max height, `1..12` (`0x0C`). **Unreliable** when any line ends with `&` — those descender lines are not counted in the height. The header height is for *line-height/advance*, not for total height. Always read until the NUL terminator to determine actual character extent. |

After the two header bytes, the glyph body begins. Encoding depends on font type:

### Block fonts (type 0x01)
Each cell is **1 byte** = the CP437 character code to draw at that cell, with default attributes.

### Outline fonts (type 0x00)
Each cell is **1 byte** = a "letter code" that represents a position in the outline (see Outline Glyph Mapping below). Letters `A..N` map to specific CP437 box-drawing characters; `O` is a hard space (`0xF7`); `@` is a filler for leading spaces; `&` is a descender mark.

### Color fonts (type 0x02)
Each cell is **2 bytes**:
- Byte 1: CP437 character code.
- Byte 2: attribute byte. Upper nibble (`(b >> 4) & 0x0F`) is the background color index, `0..7`. Lower nibble (`b & 0x0F`) is the foreground color index, `0..15`. **`0x00` is a legal attribute byte (black on black)** — do NOT mistake it for the NUL terminator; the terminator is distinguished by being a stand-alone byte after a 0x0D line break or at the end of the glyph.

### Line terminator
A `0x0D` byte (Carriage Return) ends the current line.

### Glyph terminator
A `0x00` (NUL) byte after a 0x0D ends the current glyph.

### Empty trailing cells
If a line ends before reaching the max width, the remaining cells on that line are **transparent** (not rendered). This is normal — glyphs are not required to be rectangular.

## Outline Glyph Mapping

Outline fonts use single-letter codes to represent outline drawing characters. The mapping:

| Letter | CP437 code (hex) | Glyph | Purpose |
|---|---|---|---|
| A | `0xCD` | ═ | Double horizontal beam |
| B | `0xC4` | ─ | Single horizontal beam |
| C | `0xB3` | │ | Single vertical beam |
| D | `0xBA` | ║ | Double vertical beam |
| E | `0xD5` | ╒ | Upper-left outer corner (outside) / Up-to-Right outer corner (inside) |
| F | `0xBB` | ╗ | Upper-right outer corner (outside) / Right-to-Down outer corner (inside) |
| G | `0xD6` | ╓ | Up-to-Right inner corner (outside) / Upper-left inner corner (inside) |
| H | `0xBF` | ┐ | Right-to-Down inner corner (outside) / Upper-right inner corner (inside) |
| I | `0xC8` | ╚ | Lower-left inner corner (inside) |
| J | `0xBE` | ╛ | Lower-right inner corner (inside) |
| K | `0xC0` | └ | Lower-left outer corner (outside) |
| L | `0xBD` | ╜ | Lower-right outer corner (outside) |
| M | `0xB5` | ╡ | (per spec — purpose unclear in source) |
| N | `0xC7` | ╟ | (per spec — purpose unclear in source) |
| O | `0xF7` | ≈ | Hard space (renders as a solid space cell inside the glyph) |
| `@` | `0x40` | (filler) | Filler for leading spaces — not rendered as content |
| `&` | `0x26` | (marker) | Descender mark — line is not counted by max-height |

Outline-font drawing rules per Roy/SAC's documentation: double lines form the rightmost side of a column and the topmost side of a beam.

## Color table (16-color EGA, attribute byte indices)

| Index | Color |
|---|---|
| 0 | Black |
| 1 | Blue |
| 2 | Green |
| 3 | Cyan |
| 4 | Red |
| 5 | Magenta |
| 6 | Brown |
| 7 | Light Gray |
| 8 | Dark Gray |
| 9 | Bright Blue |
| 10 | Bright Green |
| 11 | Bright Cyan |
| 12 | Bright Red |
| 13 | Bright Magenta |
| 14 | Yellow |
| 15 | White |

Background indices are restricted to `0..7`; foreground may be `0..15`.

## Edge cases and gotchas

- **Block-size overflow.** The 2-byte block-size field caps individual font character data at 65,534 bytes (0xFFFE; 0xFFFF is the "undefined offset" sentinel). For a color font using 2 bytes per cell + max 30×12 cells + line breaks + NUL per glyph for 94 glyphs, the maximum offset is reached well before glyph 93. Real-world large color fonts may need to share offsets via the "Copy character" feature.
- **Copied glyphs share offset.** If two glyphs were created via TDFONTS.EXE's Copy command and neither was modified afterward, both will point to the same data offset. This is a legitimate space-saving technique and a writer should detect and emit identical offsets when two glyphs have byte-identical data.
- **Outline reserved letters.** Outline fonts use specific letters for specific purposes; the file format does not enforce these rules — only the TDFONTS.EXE editor does. A library writing an outline font must validate the constraint itself or risk producing files that work but don't render correctly under the original rules.
- **Hard spaces.** Outline glyph `O` (letter O, not zero) maps to CP437 `0xF7` and is used for the *interior* of solid columns/beams. Confusingly, in real-world rendering it is shown as ▓-style block in TDFONTS, not as the actual CP437 0xF7 character.
- **Descender lines.** Lines terminated with `&` are below the baseline. They are part of the glyph but excluded from the line-height calculation so cursor positioning doesn't shift between letters with and without descenders.

## SwiftTDF compliance posture

SwiftTDF treats this document as the source of truth. Where the spec is ambiguous, the library:

- Reads liberally: any encoding the original TDFONTS.EXE accepted should round-trip cleanly.
- Writes conservatively: produces output that the original TDFONTS.EXE editor accepts without complaint.
- Preserves shared offsets when glyph data is byte-identical (matches the "Copy character" optimization).
- Distinguishes color-attribute `0x00` from the NUL terminator structurally (by position, after 0x0D), never by byte value alone.
