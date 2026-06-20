// TDFFont.swift
// SwiftTDF — one font within a collection.

/// One TheDraw font: name, type, spacing, and a sparse map of glyphs keyed
/// by ASCII code.
///
/// Glyphs are stored as a dictionary keyed by ASCII code (`33..126`). Missing
/// keys are encoded by the writer as the spec's "glyph undefined" sentinel
/// (`0xFFFF`).
public struct TDFFont: Sendable, Hashable, Codable {
    /// Font name. Spec limits this to **12 ASCII bytes**; the encoder is
    /// responsible for truncation. Not validated at the type level so that
    /// in-memory editing can hold longer strings temporarily.
    public var name: String
    /// Font type, controlling per-cell encoding.
    public var type: TDFFontType
    /// Letter spacing in cells, `0..40` per spec.
    ///
    /// Stored here as the **decoded** value (`0..40`). The on-disk byte is
    /// `letterSpacing + 1` (range `0x01..0x29`); the encoder handles that
    /// adjustment.
    public var letterSpacing: UInt8
    /// Sparse glyph map keyed by ASCII code. Only codes in
    /// ``definedASCIIRange`` are meaningful for the on-disk format.
    public var characters: [UInt8: TDFCharacter]

    /// Memberwise initializer.
    public init(
        name: String,
        type: TDFFontType,
        letterSpacing: UInt8 = 0,
        characters: [UInt8: TDFCharacter] = [:]
    ) {
        self.name = name
        self.type = type
        self.letterSpacing = letterSpacing
        self.characters = characters
    }

    /// Convenience subscript for glyph access by ASCII code.
    public subscript(ascii: UInt8) -> TDFCharacter? {
        get { characters[ascii] }
        set { characters[ascii] = newValue }
    }

    /// The inclusive ASCII range covered by the on-disk offset table:
    /// `'!'` (33) through `'~'` (126).
    public static let definedASCIIRange: ClosedRange<UInt8> = 33...126

    /// `true` if any glyph in this font contains at least one descender line
    /// (a line terminated with `&` in the source).
    public var isDescenderUsed: Bool {
        for character in characters.values {
            for line in character.lines where line.isDescender {
                return true
            }
        }
        return false
    }
}
