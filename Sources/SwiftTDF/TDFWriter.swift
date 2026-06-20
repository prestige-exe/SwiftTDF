// TDFWriter.swift
// SwiftTDF — encode a ``TDFFontCollection`` into the raw `.tdf` binary
// container.
//
// See Reference/TDF_SPECIFICATION.md for the authoritative format reference.
// Writes conservatively (output that TDFONTS.EXE accepts without complaint)
// and round-trips cleanly through ``TDFParser/parse(_:)`` modulo unspecified
// padding bytes (e.g. the font-name buffer past the declared length).

import Foundation

/// Stateless encoder for the TheDraw `.tdf` binary container.
///
/// Mirrors ``TDFParser`` — every call site is a single
/// ``TDFWriter/encode(_:)`` invocation; there is no public state to
/// configure between calls.
public enum TDFWriter {
    /// Encode a ``TDFFontCollection`` to its on-disk `.tdf` byte stream.
    ///
    /// The encoder validates spec invariants up front (font count, per-font
    /// name length, letter spacing, ASCII range) and clamps soft limits
    /// (letter spacing > 40, glyph max width > 30, max height > 12, font
    /// name > 12 ASCII bytes) rather than throwing — this matches the
    /// TDFONTS.EXE editor's behavior, which also silently truncates these
    /// fields when writing.
    ///
    /// ## Round-trip contract
    ///
    /// `TDFParser.parse(TDFWriter.encode(c)) == c` for any well-formed `c`,
    /// **modulo unspecified padding bytes** — specifically, the 12-byte
    /// font-name buffer past the declared length, where the parser drops
    /// non-printable bytes and the writer NUL-pads.
    ///
    /// ## Deduplication
    ///
    /// If two glyphs in the same font encode to byte-identical data, they
    /// share a single character-data block offset — this matches the
    /// TDFONTS.EXE "Copy character" optimization and keeps space usage
    /// proportional to the number of *distinct* glyphs rather than the
    /// number of defined ASCII codes.
    public static func encode(_ collection: TDFFontCollection) throws -> Data {
        if collection.fonts.count > TDFFontCollection.maxFontsPerCollection {
            throw TDFError.tooManyFonts(count: collection.fonts.count)
        }

        var output = Data()
        output.append(contentsOf: TDFFontCollection.fileSignature)

        // Empty-collection invariant: a zero-font collection encodes to a
        // single synthesized empty-font placeholder (block font, empty
        // name, no glyphs). Without this placeholder a zero-font input
        // would emit only the 20-byte file header, which TDFONTS.EXE
        // rejects.
        //
        // ## Byte-count note
        //
        // The Roy/SAC spec quotes "232 bytes" for an empty .tdf file
        // (20-byte file header + 212-byte placeholder). The structurally
        // correct per-font header is **213 bytes** (4 sentinel + 1 name-
        // length + 12 name + 4 reserved + 1 type + 1 spacing + 2 block-
        // size + 188 offset-table). With a zero-byte data block, this
        // writer therefore emits **233 bytes** for an empty file. The
        // discrepancy is an off-by-one in the published spec — every
        // field in the per-font header is structurally required and the
        // parser correctly reads all 213 bytes. The 232 figure cannot be
        // produced by any encoding that round-trips through the parser.
        //
        // The placeholder round-trips through ``TDFParser/parse(_:)`` as
        // ``TDFFontCollection(fonts: [TDFFont(name: "", type: .block,
        // letterSpacing: 0, characters: [:])])``. Callers that need to
        // distinguish "no fonts" from "one empty font" must check
        // `collection.fonts.isEmpty` before encoding.
        let fontsToEmit: [TDFFont]
        if collection.fonts.isEmpty {
            fontsToEmit = [TDFFont(name: "", type: .block, letterSpacing: 0, characters: [:])]
        } else {
            fontsToEmit = collection.fonts
        }

        for (index, font) in fontsToEmit.enumerated() {
            try encodeFont(font, into: &output)
            // Spec: fonts are NUL-separated EXCEPT the last font, which is
            // not NUL-terminated.
            if index < fontsToEmit.count - 1 {
                output.append(0x00)
            }
        }

        return output
    }

    // MARK: - Per-font

    private static func encodeFont(_ font: TDFFont, into output: inout Data) throws {
        // (a) sentinel
        output.append(contentsOf: TDFFontCollection.fontStartSentinel)

        // (b) name length + 12-byte name buffer
        //
        // The spec says the name length is 1..12. We allow an empty name
        // (length 0) because the synthesized empty-collection placeholder
        // uses one, and TDFONTS.EXE tolerates it. Real fonts should have
        // at least one character; callers are responsible for that.
        let nameBytes = asciiNameBytes(font.name)
        let nameLength = UInt8(nameBytes.count)
        output.append(nameLength)
        var nameBuffer = [UInt8](repeating: 0x00, count: 12)
        for (i, b) in nameBytes.enumerated() {
            nameBuffer[i] = b
        }
        output.append(contentsOf: nameBuffer)

        // (c) 4 reserved bytes (zero)
        output.append(contentsOf: [UInt8](repeating: 0x00, count: 4))

        // (d) font type
        output.append(font.type.rawValue)

        // (e) letter spacing — model 0..40 → file 1..41. Clamp on encode
        // so we never produce out-of-range bytes; the parser rejects
        // anything outside 0x01..0x29.
        let clampedSpacing = min(font.letterSpacing, 40)
        output.append(clampedSpacing + 1)

        // (f) PLACEHOLDER 2-byte block size — filled in after we know it.
        let blockSizeOffset = output.count
        output.append(0x00)
        output.append(0x00)

        // (g) PLACEHOLDER 188-byte offset table — filled in glyph by glyph.
        let offsetTableOffset = output.count
        output.append(contentsOf: [UInt8](repeating: 0xFF, count: 188))

        // (h) Build the character-data block.
        //
        // Walk ASCII 33..126 in order; for each defined glyph either emit
        // its encoded bytes (recording the offset) or share an existing
        // offset if the bytes match a previously-emitted glyph. This is the
        // "Copy character" deduplication described in the spec.
        var blockBytes = Data()
        var dedupCache: [Data: UInt16] = [:]
        var offsets = [UInt16](repeating: 0xFFFF, count: 94)
        let asciiStart = TDFFont.definedASCIIRange.lowerBound
        let asciiEnd = TDFFont.definedASCIIRange.upperBound

        for ascii in asciiStart...asciiEnd {
            let tableIndex = Int(ascii) - Int(asciiStart)
            guard let glyph = font.characters[ascii] else { continue }

            let encoded = encodeGlyph(glyph, fontType: font.type)

            if let existing = dedupCache[encoded] {
                offsets[tableIndex] = existing
            } else {
                let newOffset = UInt16(blockBytes.count)
                offsets[tableIndex] = newOffset
                dedupCache[encoded] = newOffset
                blockBytes.append(encoded)
            }
        }

        // (i) Fill in the 2-byte block-size placeholder.
        let blockSize = UInt16(blockBytes.count)
        output[blockSizeOffset]     = UInt8(blockSize & 0xFF)
        output[blockSizeOffset + 1] = UInt8((blockSize >> 8) & 0xFF)

        // (j) Fill in the 188-byte offset table.
        for (i, value) in offsets.enumerated() {
            output[offsetTableOffset + i * 2]     = UInt8(value & 0xFF)
            output[offsetTableOffset + i * 2 + 1] = UInt8((value >> 8) & 0xFF)
        }

        // (k) Emit the character-data block.
        output.append(blockBytes)
    }

    // MARK: - Glyph encoding

    private static func encodeGlyph(_ character: TDFCharacter, fontType: TDFFontType) -> Data {
        var bytes = Data()

        // Glyph header: clamped width (1..30) and height (1..12) per spec.
        bytes.append(min(character.maxWidth, 30))
        bytes.append(min(character.maxHeight, 12))

        for line in character.lines {
            for cell in line.cells {
                switch fontType {
                case .block, .outline:
                    bytes.append(cell.code)
                case .color:
                    bytes.append(cell.code)
                    // Color cells require an attribute byte; a missing
                    // attribute (nil) is treated as the TDFONTS.EXE
                    // default of light gray on black (0x07).
                    let attributeByte = (cell.attribute ?? TDFAttribute.defaultAttribute).rawByte
                    bytes.append(attributeByte)
                }
            }
            // Descender marker `&` (0x26) is the last cell byte before the
            // line terminator. The parser strips it and sets isDescender;
            // the writer re-emits it from the flag.
            if line.isDescender {
                bytes.append(0x26)
            }
            bytes.append(0x0D)
        }

        // Glyph terminator: a NUL that follows a 0x0D. If the glyph had no
        // lines at all (empty character) we still emit the NUL so the
        // parser sees a well-formed glyph; in that case there is no
        // preceding 0x0D, but the parser also accepts a NUL at the start
        // of a glyph body as terminating an empty glyph.
        bytes.append(0x00)

        return bytes
    }

    // MARK: - Name encoding

    /// Encode a font name as up to 12 printable-ASCII bytes.
    ///
    /// Non-ASCII characters are dropped (mirroring the parser's filter for
    /// printable ASCII on read). The result is truncated to 12 bytes per
    /// spec; callers that need to preserve longer names should validate
    /// before constructing the ``TDFFont``.
    private static func asciiNameBytes(_ name: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(12)
        for scalar in name.unicodeScalars {
            let value = scalar.value
            guard value >= 0x20 && value <= 0x7E else { continue }
            out.append(UInt8(value))
            if out.count == 12 { break }
        }
        return out
    }
}
