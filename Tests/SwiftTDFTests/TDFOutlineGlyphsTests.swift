// TDFOutlineGlyphsTests.swift
// SwiftTDF — verify the outline-letter → CP437 mapping table matches the
// spec verbatim, and that unmapped letters pass through unchanged.

import XCTest
@testable import SwiftTDF

final class TDFOutlineGlyphsTests: XCTestCase {

    // MARK: - Per-letter mappings (one assertion each, per the spec table)

    func testLetterAMapsToDoubleHorizontal() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x41), 0xCD)
    }

    func testLetterBMapsToSingleHorizontal() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x42), 0xC4)
    }

    func testLetterCMapsToSingleVertical() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x43), 0xB3)
    }

    func testLetterDMapsToDoubleVertical() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x44), 0xBA)
    }

    func testLetterEMapsToUpperLeftOuter() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x45), 0xD5)
    }

    func testLetterFMapsToUpperRightOuter() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x46), 0xBB)
    }

    func testLetterGMapsToUpperLeftInner() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x47), 0xD6)
    }

    func testLetterHMapsToUpperRightInner() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x48), 0xBF)
    }

    func testLetterIMapsToLowerLeftInner() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x49), 0xC8)
    }

    func testLetterJMapsToLowerRightInner() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x4A), 0xBE)
    }

    func testLetterKMapsToLowerLeftOuter() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x4B), 0xC0)
    }

    func testLetterLMapsToLowerRightOuter() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x4C), 0xBD)
    }

    func testLetterMMapsToRightTee() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x4D), 0xB5)
    }

    func testLetterNMapsToLeftTee() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x4E), 0xC7)
    }

    func testLetterOMapsToHardSpace() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x4F), 0xF7)
    }

    // MARK: - Unmapped letters fall through

    /// 'Z' (0x5A) has no entry in the outline mapping table; it must render
    /// as itself per the "letters not in this table render as the literal
    /// byte" rule.
    func testUnmappedLetterFallsThrough() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x5A), 0x5A,
                       "'Z' should pass through unchanged")
    }

    /// Spot-check a couple more outside the mapped range so we're not just
    /// relying on Z.
    func testLowercaseAndDigitFallThrough() {
        XCTAssertEqual(TDFOutlineGlyphs.render(0x61), 0x61, "'a' should pass through")
        XCTAssertEqual(TDFOutlineGlyphs.render(0x30), 0x30, "'0' should pass through")
    }

    // MARK: - Filler / descender markers

    /// `@` (0x40) is the outline-font filler and must be flagged accordingly.
    func testFillerMarkerRecognized() {
        XCTAssertTrue(TDFOutlineGlyphs.isFiller(0x40))
        XCTAssertFalse(TDFOutlineGlyphs.isFiller(0x41))
    }

    /// `&` (0x26) is the descender marker.
    func testDescenderMarkerRecognized() {
        XCTAssertTrue(TDFOutlineGlyphs.isDescender(0x26))
        XCTAssertFalse(TDFOutlineGlyphs.isDescender(0x25))
    }
}
