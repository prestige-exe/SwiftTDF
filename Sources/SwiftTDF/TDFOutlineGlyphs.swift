// TDFOutlineGlyphs.swift
// SwiftTDF — outline-font letter-code → CP437 mapping.

/// Maps the single-byte "letter codes" used inside outline-font glyph
/// data to the CP437 code points they should render as. Per the TDF
/// spec, outline fonts store letters A..N (etc.) rather than the
/// actual box-drawing characters; the renderer must translate.
///
/// Letters not in this table render as the literal byte (TDF allows
/// arbitrary text characters in outline glyphs alongside the box-draw
/// letters).
public enum TDFOutlineGlyphs {
    public static let mapping: [UInt8: UInt8] = [
        0x41: 0xCD,  // A → ═
        0x42: 0xC4,  // B → ─
        0x43: 0xB3,  // C → │
        0x44: 0xBA,  // D → ║
        0x45: 0xD5,  // E → ╒
        0x46: 0xBB,  // F → ╗
        0x47: 0xD6,  // G → ╓
        0x48: 0xBF,  // H → ┐
        0x49: 0xC8,  // I → ╚
        0x4A: 0xBE,  // J → ╛
        0x4B: 0xC0,  // K → └
        0x4C: 0xBD,  // L → ╜
        0x4D: 0xB5,  // M → ╡
        0x4E: 0xC7,  // N → ╟
        0x4F: 0xF7,  // O → ≈ (hard space inside character)
    ]

    /// Returns the rendered CP437 byte for an outline-glyph cell.
    /// Letters with no mapping are returned as-is so text-style
    /// glyphs in outline fonts still render reasonably.
    public static func render(_ letter: UInt8) -> UInt8 {
        mapping[letter] ?? letter
    }

    /// True if the byte is a filler for leading spaces — the renderer
    /// should treat these as transparent (don't paint).
    public static func isFiller(_ byte: UInt8) -> Bool { byte == 0x40 }

    /// True if the byte is a descender marker. Should never appear
    /// in normalized TDFCharacter.lines after parsing (the parser
    /// strips it and sets line.isDescender), but exposed for
    /// completeness if downstream code is round-tripping raw bytes.
    public static func isDescender(_ byte: UInt8) -> Bool { byte == 0x26 }
}
