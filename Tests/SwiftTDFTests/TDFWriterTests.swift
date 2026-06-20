// TDFWriterTests.swift
// SwiftTDF — writer-only invariants: size, name truncation, glyph
// deduplication, and the 34-font cap.

import XCTest
@testable import SwiftTDF

final class TDFWriterTests: XCTestCase {

    // MARK: - Empty-file invariant

    /// An empty collection must encode to exactly 232 bytes on disk per the
    /// `Reference/TDF_SPECIFICATION.md` invariant.
    func testEmptyCollectionEncodesTo232Bytes() throws {
        let bytes = try TDFWriter.encode(.empty)
        XCTAssertEqual(bytes.count, 232,
                       "Empty .tdf file must be exactly 232 bytes per spec")
    }

    // MARK: - Name truncation

    /// A font name longer than 12 ASCII bytes must be silently truncated,
    /// never crash the writer. (The spec caps names at 12 bytes.)
    func testLongNameTruncatedTo12Bytes() throws {
        let longName = "ThisNameIsWayTooLongForTheFormat"
        XCTAssertGreaterThan(longName.count, 12)

        let font = TDFFont(
            name: longName,
            type: .block,
            letterSpacing: 0,
            characters: [:]
        )
        let bytes = try TDFWriter.encode(TDFFontCollection(fonts: [font]))

        // Per the spec, after the 20-byte file header + 4-byte sentinel,
        // offset 24 is the name-length byte and 25..36 is the 12-byte name
        // buffer. The writer should clamp the name length to 12.
        XCTAssertEqual(bytes[24], 12, "name length byte must be capped at 12")

        // Round-trip: the parsed name should be the first 12 ASCII chars.
        let parsed = try TDFParser.parse(bytes)
        let expected = String(longName.prefix(12))
        XCTAssertEqual(parsed.fonts.first?.name, expected,
                       "parsed name must equal first 12 chars of source")
    }

    // MARK: - Glyph deduplication

    /// Two glyphs with byte-identical encoded content must share a single
    /// offset in the character-data block — the "Copy character"
    /// optimization described in the spec.
    func testDuplicateGlyphsShareOffset() throws {
        // '!' (0x21) and 'A' (0x41) get identical 1x1 block content.
        let identical = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [TDFCell(code: 0xDB)])]
        )
        let font = TDFFont(
            name: "Dupe",
            type: .block,
            letterSpacing: 0,
            characters: [0x21: identical, 0x41: identical]
        )
        let bytes = try TDFWriter.encode(TDFFontCollection(fonts: [font]))

        // Offset table starts at 20 (file header) + 4 (sentinel) + 1 (name
        // len) + 12 (name) + 4 (reserved) + 1 (type) + 1 (spacing)
        // + 2 (block size) = 45.
        let offsetTableStart = 45

        // 94 LE UInt16 offsets cover ASCII 33..126.
        func offset(forASCII ascii: UInt8) -> UInt16 {
            let index = Int(ascii) - 33
            let lo = bytes[offsetTableStart + index * 2]
            let hi = bytes[offsetTableStart + index * 2 + 1]
            return UInt16(lo) | (UInt16(hi) << 8)
        }

        let bangOffset = offset(forASCII: 0x21)
        let aOffset = offset(forASCII: 0x41)

        XCTAssertNotEqual(bangOffset, 0xFFFF, "'!' should be defined")
        XCTAssertNotEqual(aOffset, 0xFFFF, "'A' should be defined")
        XCTAssertEqual(bangOffset, aOffset,
                       "byte-identical glyphs must share the same data offset")
    }

    /// As a sanity check on the deduplication: two glyphs with *different*
    /// content must NOT share an offset.
    func testDistinctGlyphsHaveDistinctOffsets() throws {
        let g1 = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [TDFCell(code: 0xDB)])]
        )
        let g2 = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [TDFCell(code: 0xB0)])]
        )
        let font = TDFFont(
            name: "NoDupe",
            type: .block,
            letterSpacing: 0,
            characters: [0x21: g1, 0x41: g2]
        )
        let bytes = try TDFWriter.encode(TDFFontCollection(fonts: [font]))

        let offsetTableStart = 45
        func offset(forASCII ascii: UInt8) -> UInt16 {
            let index = Int(ascii) - 33
            let lo = bytes[offsetTableStart + index * 2]
            let hi = bytes[offsetTableStart + index * 2 + 1]
            return UInt16(lo) | (UInt16(hi) << 8)
        }
        XCTAssertNotEqual(offset(forASCII: 0x21), offset(forASCII: 0x41),
                          "distinct glyphs must have distinct offsets")
    }

    // MARK: - Font-count cap

    /// The spec caps a collection at 34 fonts; the writer must throw
    /// `.tooManyFonts` rather than silently truncate or crash.
    func testTooManyFontsRejected() {
        let placeholder = TDFFont(
            name: "X", type: .block, letterSpacing: 0, characters: [:]
        )
        let fonts = Array(repeating: placeholder, count: 35)
        let collection = TDFFontCollection(fonts: fonts)

        XCTAssertThrowsError(try TDFWriter.encode(collection)) { error in
            XCTAssertEqual(error as? TDFError, .tooManyFonts(count: 35))
        }
    }
}
