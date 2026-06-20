// TDFCell.swift
// SwiftTDF — one cell of glyph content.

/// One cell within a ``TDFCharacter`` line.
///
/// For block and outline fonts, only ``code`` is meaningful (the spec writes
/// 1 byte per cell). For color fonts, ``attribute`` carries the foreground/
/// background pair encoded as the cell's second byte. A `nil` attribute
/// indicates a non-color cell — it is **not** equivalent to the default
/// attribute byte (`0x07`).
public struct TDFCell: Sendable, Hashable, Codable {
    /// CP437 character code (block/color fonts) or outline letter code
    /// (outline fonts; see the outline glyph mapping in the spec).
    public var code: UInt8
    /// Color attribute for color-font cells; `nil` for block and outline fonts.
    public var attribute: TDFAttribute?

    /// Memberwise initializer.
    public init(code: UInt8, attribute: TDFAttribute? = nil) {
        self.code = code
        self.attribute = attribute
    }

    /// A transparent placeholder cell — CP437 space (`0x20`), no attribute.
    /// Used for sparse/undefined positions in non-rectangular glyphs.
    public static let empty = TDFCell(code: 0x20, attribute: nil)
}
