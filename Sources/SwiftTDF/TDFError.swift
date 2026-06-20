// TDFError.swift
// SwiftTDF — errors thrown by the parser (and, later, the writer).

import Foundation

/// Errors produced while decoding a `.tdf` byte stream into a
/// ``TDFFontCollection``.
///
/// All values include enough positional context (offset, font index, ASCII
/// code) for a caller to point at the offending byte without re-walking the
/// file. Conforms to `LocalizedError` so the descriptions surface usefully
/// when reported via `Error`-typed channels.
public enum TDFError: Error, Sendable, Equatable {
    /// The input buffer is smaller than the fixed 20-byte file header.
    case fileTooShort
    /// The 20-byte file header did not match `0x13 "TheDraw FONTS file" 0x1A`.
    case invalidSignature
    /// A per-font header did not begin with the `0x55 0xAA 0x00 0xFF`
    /// start-of-font sentinel. `at` is the absolute byte offset where the
    /// sentinel was expected.
    case invalidFontSentinel(at: Int)
    /// The font-type byte (offset 21 of the per-font header) was not one of
    /// the values defined by ``TDFFontType``.
    case invalidFontType(UInt8)
    /// The letter-spacing byte (offset 22 of the per-font header) was outside
    /// the legal `0x01..0x29` range (decoded `0..40`).
    case invalidLetterSpacing(UInt8)
    /// A glyph's character-data ran past the end of the font's character-data
    /// block (or end of file). `font` is the zero-based font index; `ascii`
    /// is the glyph's ASCII code.
    case characterDataTruncated(font: Int, ascii: UInt8)
    /// The collection contained more than the spec maximum of 34 fonts.
    /// `count` is the number actually read.
    case tooManyFonts(count: Int)
}

extension TDFError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileTooShort:
            return "TDF file is shorter than the required 20-byte file header."
        case .invalidSignature:
            return "TDF file header signature is invalid (expected 0x13 + \"TheDraw FONTS file\" + 0x1A)."
        case .invalidFontSentinel(let offset):
            return "Invalid font start-of-font sentinel at offset \(offset) (expected 55 AA 00 FF)."
        case .invalidFontType(let raw):
            return String(format: "Invalid TDF font-type byte 0x%02X (expected 0x00 outline, 0x01 block, or 0x02 color).", raw)
        case .invalidLetterSpacing(let raw):
            return String(format: "Invalid TDF letter-spacing byte 0x%02X (expected 0x01..0x29).", raw)
        case .characterDataTruncated(let font, let ascii):
            return "Truncated character data in font \(font) at ASCII code \(ascii)."
        case .tooManyFonts(let count):
            return "TDF collection holds \(count) fonts, exceeding the spec maximum of \(TDFFontCollection.maxFontsPerCollection)."
        }
    }
}
