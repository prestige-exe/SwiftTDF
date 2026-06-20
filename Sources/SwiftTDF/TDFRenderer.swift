// TDFRenderer.swift
// SwiftTDF — pure-data rasterizer from a ``TDFCharacter`` to a grid of
// painted cells. No SwiftUI, no AppKit/UIKit; consumers layer their own
// drawing on top of ``TDFRenderedCell``.

/// One painted cell in a rendered glyph row.
///
/// The renderer already applied the outline-letter → CP437 translation
/// (for outline fonts) and resolved attributes (block uses the
/// caller-supplied default, color uses the cell's own attribute). The
/// consumer just needs to draw ``code`` with ``foreground`` / ``background``
/// — unless ``isFiller`` is true, in which case the cell is transparent.
public struct TDFRenderedCell: Sendable, Hashable {
    /// CP437 byte to render (already outline-translated where applicable).
    public var code: UInt8
    /// EGA foreground color index, `0..15`.
    public var foreground: UInt8
    /// EGA background color index, `0..7`.
    public var background: UInt8
    /// `true` when the source byte was an outline-font filler (`@`) —
    /// the consumer should treat the cell as transparent and not paint.
    public var isFiller: Bool
    /// `true` when the source byte was the outline-font hard-space code
    /// (`O` → `≈`); the cell paints a solid in-glyph space.
    public var isHardSpace: Bool

    /// Memberwise initializer.
    public init(
        code: UInt8,
        foreground: UInt8,
        background: UInt8,
        isFiller: Bool = false,
        isHardSpace: Bool = false
    ) {
        self.code = code
        self.foreground = foreground
        self.background = background
        self.isFiller = isFiller
        self.isHardSpace = isHardSpace
    }
}

/// Pure-data rasterizer for ``TDFCharacter``.
///
/// Namespaced as an empty `enum` — every call site is a single
/// ``TDFRenderer/render(_:type:defaultAttribute:)`` invocation. No state
/// is shared between calls.
public enum TDFRenderer {
    /// Render a glyph to a row-major grid of ``TDFRenderedCell``.
    ///
    /// - Parameters:
    ///   - char: the glyph to render.
    ///   - type: the parent font's type, which selects the per-cell
    ///     decoding strategy (block/color/outline).
    ///   - defaultAttribute: foreground/background used for block and
    ///     outline fonts — color fonts ignore this and use the cell's
    ///     own attribute.
    /// - Returns: `rows × cols` cells. The outer array has
    ///   `char.lines.count` entries (including descender lines, in
    ///   their original order). Each inner array is padded only to the
    ///   line's actual length — trailing transparent cells beyond
    ///   `cells.count` are not materialized.
    public static func render(
        _ char: TDFCharacter,
        type: TDFFontType,
        defaultAttribute: TDFAttribute = .defaultAttribute
    ) -> [[TDFRenderedCell]] {
        var rows: [[TDFRenderedCell]] = []
        rows.reserveCapacity(char.lines.count)

        for line in char.lines {
            var row: [TDFRenderedCell] = []
            row.reserveCapacity(line.cells.count)
            for cell in line.cells {
                row.append(renderCell(cell, type: type, defaultAttribute: defaultAttribute))
            }
            rows.append(row)
        }

        return rows
    }

    /// Translate a single ``TDFCell`` according to its font type.
    private static func renderCell(
        _ cell: TDFCell,
        type: TDFFontType,
        defaultAttribute: TDFAttribute
    ) -> TDFRenderedCell {
        switch type {
        case .block:
            return TDFRenderedCell(
                code: cell.code,
                foreground: defaultAttribute.foreground,
                background: defaultAttribute.background
            )

        case .color:
            // Color cells carry their own attribute. If a writer omitted
            // it (shouldn't happen for a well-formed color font, but the
            // parser permits it via `attribute: nil`), fall back to the
            // caller's default rather than crashing.
            let attribute = cell.attribute ?? defaultAttribute
            return TDFRenderedCell(
                code: cell.code,
                foreground: attribute.foreground,
                background: attribute.background
            )

        case .outline:
            let source = cell.code
            let translated = TDFOutlineGlyphs.render(source)
            return TDFRenderedCell(
                code: translated,
                foreground: defaultAttribute.foreground,
                background: defaultAttribute.background,
                isFiller: TDFOutlineGlyphs.isFiller(source),
                isHardSpace: source == 0x4F
            )
        }
    }
}

// MARK: - Convenience

public extension TDFCharacter {
    /// Render this glyph to a row-major grid of ``TDFRenderedCell``.
    /// Equivalent to ``TDFRenderer/render(_:type:defaultAttribute:)``.
    func rendered(
        type: TDFFontType,
        defaultAttribute: TDFAttribute = .defaultAttribute
    ) -> [[TDFRenderedCell]] {
        TDFRenderer.render(self, type: type, defaultAttribute: defaultAttribute)
    }
}
