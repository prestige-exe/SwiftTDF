// TDFFontType.swift
// SwiftTDF — TheDraw font type discriminator.

/// The three TheDraw font types defined by byte 21 of a font header.
///
/// Layout in the .tdf file is byte-for-byte different per type — see
/// ``TDFCharacter`` for the encoding details:
///
/// - ``outline``: 1 byte per cell, a "letter code" mapping to box-drawing characters.
/// - ``block``: 1 byte per cell, the raw CP437 character code.
/// - ``color``: 2 bytes per cell, CP437 code + attribute byte.
public enum TDFFontType: UInt8, Sendable, CaseIterable, Codable {
    case outline = 0x00
    case block = 0x01
    case color = 0x02
}
