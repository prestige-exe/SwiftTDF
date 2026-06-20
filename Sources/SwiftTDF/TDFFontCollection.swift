// TDFFontCollection.swift
// SwiftTDF — file-level model: a collection of up to 34 TDF fonts.

/// A TheDraw font file: zero or more ``TDFFont`` entries plus the on-disk
/// invariants needed by the parser/writer.
///
/// ## On-disk layout (per Roy/SAC, see `Reference/TDF_SPECIFICATION.md`)
///
/// An **empty** `.tdf` file is exactly **232 bytes**:
///
/// ```
///   offsets 0..19   (20 bytes)  file header  — see fileSignature
///   offsets 20..23  ( 4 bytes)  font-1 start-of-font sentinel
///   offsets 24..231 (208 bytes) font-1 placeholder metadata
/// ```
///
/// The per-font header is exposed as ``fontHeaderSize`` = **212 bytes**. This
/// figure follows Roy/SAC's accounting:
///
/// ```
///   4-byte sentinel + 1-byte name length + 12-byte name + 4 reserved
///   + 1 type + 1 spacing + 2 block-size + 188 (94 × 2) offsets = 213
/// ```
///
/// 213 is the raw sum, but the spec quotes 212 because the inter-font
/// **separator** in multi-font collections (NUL between font N's data and
/// font N+1's sentinel) is accounted for once outside the per-font header.
/// We mirror the spec's number here and let the writer reconcile the
/// boundary bytes explicitly. The empty-file invariant (`20 + 212 == 232`)
/// is verified by tests.
///
/// ## Multi-font separator
///
/// Fonts in the collection are NUL-separated **except** the last font, which
/// is not NUL-terminated.
public struct TDFFontCollection: Sendable, Codable {
    /// Fonts in this collection, in file order. Spec maximum is 34
    /// (``maxFontsPerCollection``); not enforced at the type level so that
    /// editors can hold over-capacity collections during editing.
    public var fonts: [TDFFont]

    /// Memberwise initializer.
    public init(fonts: [TDFFont] = []) {
        self.fonts = fonts
    }

    /// A collection with no fonts.
    public static let empty = TDFFontCollection(fonts: [])

    // MARK: - On-disk constants

    /// The 20-byte file header: `0x13 "TheDraw FONTS file" 0x1A`.
    public static let fileSignature: [UInt8] = {
        var bytes: [UInt8] = [0x13]
        bytes.append(contentsOf: Array("TheDraw FONTS file".utf8))
        bytes.append(0x1A)
        return bytes
    }()

    /// The 4-byte start-of-font sentinel: `0x55 0xAA 0x00 0xFF`.
    public static let fontStartSentinel: [UInt8] = [0x55, 0xAA, 0x00, 0xFF]

    /// Maximum fonts allowed per collection by the spec.
    public static let maxFontsPerCollection = 34

    /// Size of the file header in bytes (offsets 0..19).
    public static let fileHeaderSize = 20

    /// Size of one per-font header in bytes, per Roy/SAC's accounting.
    /// See the type documentation for the byte-by-byte breakdown.
    public static let fontHeaderSize = 212
}
