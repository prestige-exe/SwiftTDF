// TDFParser.swift
// SwiftTDF — decode raw .tdf bytes into a ``TDFFontCollection``.
//
// See Reference/TDF_SPECIFICATION.md for the authoritative format reference.
// Reads liberally (accepts anything TDFONTS.EXE would have produced) and
// surfaces all positional context through ``TDFError`` so callers can point
// at the offending byte without re-walking the file.

import Foundation

/// Stateless decoder for the TheDraw `.tdf` binary container.
///
/// The decoder is intentionally namespaced as an empty `enum` — every call
/// site is a `TDFParser.parse(_:)` invocation that fully consumes its input.
/// Internal helpers are private file-scope; there is no public state to
/// configure or share between calls.
public enum TDFParser {
    /// Decode a `.tdf` file into a ``TDFFontCollection``.
    ///
    /// The parser bounds-checks every read and throws ``TDFError`` on the
    /// first failure that can't be locally recovered. It will, however,
    /// continue past the spec's 34-font cap and report the count via
    /// ``TDFError/tooManyFonts(count:)`` only after walking the whole
    /// collection — callers that want partial recovery can catch this
    /// error and re-run the parser themselves with a trimmed buffer.
    public static func parse(_ data: Data) throws -> TDFFontCollection {
        var cursor = Cursor(data: data)
        try validateFileHeader(&cursor)

        var fonts: [TDFFont] = []

        // The very first font's sentinel must be present immediately after
        // the 20-byte file header. Subsequent fonts are NUL-separated; the
        // separator is consumed at the bottom of the loop iff there is more
        // data left after the current font.
        while cursor.remaining > 0 {
            let fontIndex = fonts.count
            let font = try readFont(&cursor, fontIndex: fontIndex)
            fonts.append(font)

            // Spec: fonts are NUL-separated EXCEPT the last font. If there's
            // any data left, the next byte should be the 0x00 separator and
            // then the next font's sentinel. Tolerate a stray trailing NUL
            // after the last font too — some writers emit one.
            if cursor.remaining > 0 {
                let separator = try cursor.readUInt8()
                // A NUL separator is the only valid continuation; if the
                // following byte starts the sentinel directly (because the
                // separator was actually a content byte misclassified by an
                // older writer), let the next iteration's sentinel check
                // produce a precise error.
                if separator != 0x00 && cursor.remaining > 0 {
                    // Rewind so the sentinel check sees this byte.
                    cursor.position -= 1
                }
            }
        }

        if fonts.count > TDFFontCollection.maxFontsPerCollection {
            throw TDFError.tooManyFonts(count: fonts.count)
        }

        // Empty-collection round-trip: the writer synthesizes a placeholder
        // font (empty name, block type, no glyphs) for empty collections so
        // the output is still a structurally valid TDFONTS.EXE file. Reverse
        // that here so `parse(encode(.empty)) == .empty` — without this the
        // round-trip would yield a 1-font collection containing the
        // placeholder.
        if fonts.count == 1, isEmptyPlaceholder(fonts[0]) {
            return TDFFontCollection.empty
        }

        return TDFFontCollection(fonts: fonts)
    }

    /// True for the writer's synthesized "empty collection" placeholder
    /// font: zero-length name, block type, no defined glyphs, default
    /// letter spacing. Matched here so the parser can reduce the canonical
    /// empty-file encoding back to ``TDFFontCollection/empty``.
    private static func isEmptyPlaceholder(_ font: TDFFont) -> Bool {
        return font.name.isEmpty
            && font.type == .block
            && font.letterSpacing == 0
            && font.characters.isEmpty
    }

    // MARK: - File header

    private static func validateFileHeader(_ cursor: inout Cursor) throws {
        guard cursor.remaining >= TDFFontCollection.fileHeaderSize else {
            throw TDFError.fileTooShort
        }
        let header = try cursor.readBytes(TDFFontCollection.fileHeaderSize)
        if Array(header) != TDFFontCollection.fileSignature {
            throw TDFError.invalidSignature
        }
    }

    // MARK: - Per-font

    private static func readFont(_ cursor: inout Cursor, fontIndex: Int) throws -> TDFFont {
        // (a) sentinel
        let sentinelOffset = cursor.position
        guard cursor.remaining >= 4 else {
            throw TDFError.invalidFontSentinel(at: sentinelOffset)
        }
        let sentinel = try cursor.readBytes(4)
        if Array(sentinel) != TDFFontCollection.fontStartSentinel {
            throw TDFError.invalidFontSentinel(at: sentinelOffset)
        }

        // (b) name length + 12-byte name buffer
        guard cursor.remaining >= 1 + 12 else {
            throw TDFError.characterDataTruncated(font: fontIndex, ascii: 0)
        }
        let rawNameLength = try cursor.readUInt8()
        let nameLength = min(Int(rawNameLength), 12)
        let nameBuffer = try cursor.readBytes(12)
        let name = decodeFontName(Array(nameBuffer.prefix(nameLength)))

        // (c) 4 reserved bytes
        guard cursor.remaining >= 4 else {
            throw TDFError.characterDataTruncated(font: fontIndex, ascii: 0)
        }
        _ = try cursor.readBytes(4)

        // (d) font type
        guard cursor.remaining >= 1 else {
            throw TDFError.characterDataTruncated(font: fontIndex, ascii: 0)
        }
        let typeByte = try cursor.readUInt8()
        guard let fontType = TDFFontType(rawValue: typeByte) else {
            throw TDFError.invalidFontType(typeByte)
        }

        // (e) letter spacing; on-disk range 0x01..0x29 → in-memory 0..40
        guard cursor.remaining >= 1 else {
            throw TDFError.characterDataTruncated(font: fontIndex, ascii: 0)
        }
        let spacingByte = try cursor.readUInt8()
        guard spacingByte >= 0x01 && spacingByte <= 0x29 else {
            throw TDFError.invalidLetterSpacing(spacingByte)
        }
        let letterSpacing = spacingByte - 1

        // (f) block size (LE UInt16)
        guard cursor.remaining >= 2 else {
            throw TDFError.characterDataTruncated(font: fontIndex, ascii: 0)
        }
        let blockSize = Int(try cursor.readUInt16LE())

        // (g) 94 × UInt16 LE offsets, 188 bytes total
        guard cursor.remaining >= 188 else {
            throw TDFError.characterDataTruncated(font: fontIndex, ascii: 0)
        }
        var offsets: [UInt16] = []
        offsets.reserveCapacity(94)
        for _ in 0..<94 {
            offsets.append(try cursor.readUInt16LE())
        }

        // (h) character-data block: blockSize bytes following the offset table.
        // We snapshot the block into a flat [UInt8] so glyph decoding can
        // index by `0..<blockSize` without worrying about Data's startIndex
        // offset (the input may be a slice).
        guard cursor.remaining >= blockSize else {
            throw TDFError.characterDataTruncated(font: fontIndex, ascii: 0)
        }
        let blockBytes = try cursor.readBytes(blockSize)

        // (i) decode each defined glyph
        var characters: [UInt8: TDFCharacter] = [:]
        let asciiStart = TDFFont.definedASCIIRange.lowerBound
        for (i, glyphOffset) in offsets.enumerated() {
            guard glyphOffset != 0xFFFF else { continue }
            let ascii = UInt8(Int(asciiStart) + i)
            let glyphStart = Int(glyphOffset)
            // Need at least the 2-byte glyph header.
            guard glyphStart + 2 <= blockBytes.count else {
                throw TDFError.characterDataTruncated(font: fontIndex, ascii: ascii)
            }
            let glyph = try decodeGlyph(
                in: blockBytes,
                glyphStart: glyphStart,
                fontType: fontType,
                fontIndex: fontIndex,
                ascii: ascii
            )
            characters[ascii] = glyph
        }

        return TDFFont(
            name: name,
            type: fontType,
            letterSpacing: letterSpacing,
            characters: characters
        )
    }

    // MARK: - Glyph

    private static func decodeGlyph(
        in block: [UInt8],
        glyphStart: Int,
        fontType: TDFFontType,
        fontIndex: Int,
        ascii: UInt8
    ) throws -> TDFCharacter {
        // Glyph header: 2 bytes (max width, max height). Already bounds-
        // checked by the caller.
        let maxWidth = block[glyphStart]
        let maxHeight = block[glyphStart + 1]

        var position = glyphStart + 2
        let blockEnd = block.count
        var lines: [TDFLine] = []
        var currentCells: [TDFCell] = []
        // Tracks whether the *previous* byte we consumed was a 0x0D, so we
        // can recognize a NUL terminator that immediately follows a CR. The
        // spec terminator is "0x00 after a 0x0D"; a NUL anywhere else is
        // either content (color attribute) or signals premature end of glyph
        // when we run out of buffer.
        var justEndedLine = false

        while position < blockEnd {
            let byte = block[position]

            if justEndedLine {
                // We just consumed a CR. A NUL here ends the glyph.
                if byte == 0x00 {
                    position += 1
                    return finalize(
                        maxWidth: maxWidth,
                        maxHeight: maxHeight,
                        lines: &lines,
                        currentCells: &currentCells
                    )
                }
                justEndedLine = false
            }

            if byte == 0x0D {
                // Line break: append the line we built, mark descender if
                // the last cell was `&` (0x26).
                appendLine(
                    cells: &currentCells,
                    into: &lines
                )
                position += 1
                justEndedLine = true
                continue
            }

            // Otherwise: this byte starts a cell.
            switch fontType {
            case .block, .outline:
                currentCells.append(TDFCell(code: byte, attribute: nil))
                position += 1
            case .color:
                // Color cells are 2 bytes; the second byte is the attribute
                // and 0x00 there is legal (black on black). If the buffer
                // ends mid-cell, treat as truncation.
                guard position + 1 < blockEnd else {
                    throw TDFError.characterDataTruncated(font: fontIndex, ascii: ascii)
                }
                let attributeByte = block[position + 1]
                currentCells.append(
                    TDFCell(code: byte, attribute: TDFAttribute(rawByte: attributeByte))
                )
                position += 2
            }
        }

        // Ran out of buffer without a proper NUL terminator. The spec is
        // tolerant here — finalize whatever we have. This handles the case
        // where the writer omitted a terminator for the last glyph of a
        // block.
        return finalize(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            lines: &lines,
            currentCells: &currentCells
        )
    }

    /// Append the current line to `lines`, applying the `&` descender rule.
    /// Per the spec, a line whose final cell is the literal `&` byte (0x26)
    /// is a descender line: the `&` is a marker, not content, so we drop it
    /// from the cells and flag the line.
    private static func appendLine(cells: inout [TDFCell], into lines: inout [TDFLine]) {
        var line = TDFLine(cells: cells, isDescender: false)
        if let last = cells.last, last.code == 0x26 {
            line.cells.removeLast()
            line.isDescender = true
        }
        lines.append(line)
        cells.removeAll(keepingCapacity: true)
    }

    /// Finalize a glyph: emit any trailing partial line and build the
    /// ``TDFCharacter``.
    private static func finalize(
        maxWidth: UInt8,
        maxHeight: UInt8,
        lines: inout [TDFLine],
        currentCells: inout [TDFCell]
    ) -> TDFCharacter {
        if !currentCells.isEmpty {
            appendLine(cells: &currentCells, into: &lines)
        }
        return TDFCharacter(maxWidth: maxWidth, maxHeight: maxHeight, lines: lines)
    }

    // MARK: - Name decoding

    /// Decode the first `L` bytes of a font name as ASCII, dropping NULs and
    /// non-printable bytes. The spec calls the name "ASCII"; in practice the
    /// 12-byte buffer is often padded with junk past the declared length.
    private static func decodeFontName(_ bytes: [UInt8]) -> String {
        let filtered = bytes.filter { $0 >= 0x20 && $0 <= 0x7E }
        return String(decoding: filtered, as: UTF8.self)
    }

}

// MARK: - Cursor

/// Linear bounds-checked cursor over a `Data` buffer. Throws on any read
/// past the end and surfaces the absolute byte position so the parser can
/// report precise offsets in errors.
private struct Cursor {
    let data: Data
    /// Absolute byte position. Note `Data` may start at a non-zero
    /// `startIndex` when sliced; we normalize indexing through `byte(at:)`.
    var position: Int = 0

    var remaining: Int { data.count - position }

    func byte(at index: Int) -> UInt8 {
        // Data indexing is offset-from-startIndex; this mirrors that.
        return data[data.startIndex + index]
    }

    mutating func readUInt8() throws -> UInt8 {
        guard remaining >= 1 else {
            throw TDFError.fileTooShort
        }
        let b = byte(at: position)
        position += 1
        return b
    }

    mutating func readUInt16LE() throws -> UInt16 {
        guard remaining >= 2 else {
            throw TDFError.fileTooShort
        }
        let lo = byte(at: position)
        let hi = byte(at: position + 1)
        position += 2
        return UInt16(lo) | (UInt16(hi) << 8)
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard remaining >= count else {
            throw TDFError.fileTooShort
        }
        var out: [UInt8] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            out.append(byte(at: position + i))
        }
        position += count
        return out
    }
}
