// TDFAttribute.swift
// SwiftTDF — color attribute byte for color fonts.

/// One color attribute as stored in a color-font cell's second byte.
///
/// The on-disk encoding is a single byte split into two nibbles:
/// - Low nibble (`byte & 0x0F`) — foreground color index `0..15`.
/// - Upper three bits (`(byte >> 4) & 0x07`) — background color index `0..7`.
///
/// Bit 7 is unused (background is constrained to 8 colors). See ``TDFColor``
/// for the EGA palette these indices reference.
///
/// `0x00` is a legal attribute byte (black on black) and must not be confused
/// with the glyph NUL terminator — see the format spec for terminator rules.
public struct TDFAttribute: Sendable, Hashable, Codable {
    /// Foreground color index in the 16-color EGA palette (`0..15`).
    public var foreground: UInt8
    /// Background color index in the 16-color EGA palette (`0..7`).
    public var background: UInt8

    /// Memberwise initializer. Caller is responsible for keeping the indices
    /// within their respective ranges; out-of-range values will round-trip
    /// through ``rawByte`` masked to the encodable bits.
    public init(foreground: UInt8, background: UInt8) {
        self.foreground = foreground
        self.background = background
    }

    /// Decode from the on-disk attribute byte.
    public init(rawByte: UInt8) {
        self.foreground = rawByte & 0x0F
        self.background = (rawByte >> 4) & 0x07
    }

    /// Encode to the on-disk attribute byte.
    public var rawByte: UInt8 {
        ((background & 0x07) << 4) | (foreground & 0x0F)
    }

    /// Light gray on black (`0x07`) — the default attribute used by TheDraw
    /// for newly placed cells.
    public static let defaultAttribute = TDFAttribute(foreground: 7, background: 0)
}
