# SwiftTDF

SwiftTDF is a complete Swift implementation of the TheDraw Font (`.TDF`)
file format used by the venerable DOS-era ANSI art editor. It reads any
`.TDF` file TDFONTS.EXE could produce, writes byte-compatible output that
round-trips through itself, and renders each glyph to a pure-data grid of
cells your own UI layer can paint however it likes (SwiftUI, AppKit, UIKit,
ncurses, an HTML canvas — none of that is the library's business).

Status: complete reference implementation of the TheDraw `.TDF` file format
spec. Outline, block, and color fonts; deduplicated glyph offsets; explicit
errors with byte-precise positional context; round-trip identity verified by
the test suite.

## Installation

SwiftTDF ships as a Swift package. Add it to your `Package.swift`
dependencies:

```swift
dependencies: [
    .package(url: "git@github.com:prestige-exe/SwiftTDF.git", from: "0.1.0"),
],
```

Then add `SwiftTDF` to the target(s) that need it:

```swift
.target(
    name: "MyApp",
    dependencies: ["SwiftTDF"]
)
```

The library targets Swift 6 and supports macOS 14+ and iOS 17+.

## Quick usage

### Parse a `.tdf` file

```swift
import Foundation
import SwiftTDF

let data = try Data(contentsOf: URL(fileURLWithPath: "ROY.TDF"))
let collection = try TDFParser.parse(data)

for font in collection.fonts {
    print("\(font.name) [\(font.type)] — \(font.characters.count) glyphs")
}
```

### Render a glyph to cells

```swift
guard let font = collection.fonts.first,
      let glyph = font[0x41]  // ASCII 'A'
else { return }

let rows = TDFRenderer.render(glyph, type: font.type)
for row in rows {
    for cell in row where !cell.isFiller {
        // cell.code is a CP437 byte ready to draw with
        // (cell.foreground, cell.background) from the EGA palette.
        draw(cell)
    }
}
```

### Encode a collection back to bytes

```swift
let bytes = try TDFWriter.encode(collection)
try bytes.write(to: URL(fileURLWithPath: "OUT.TDF"))
```

The writer deduplicates byte-identical glyphs (the spec's "Copy character"
optimization) and clamps soft limits — over-long names, out-of-range
letter spacing, oversized glyph dimensions — instead of throwing. Hard
invariants like the 34-font-per-collection cap are surfaced as
`TDFError.tooManyFonts`.

## Spec reference

The authoritative format reference ships with the repo:
[Reference/TDF_SPECIFICATION.md](Reference/TDF_SPECIFICATION.md). When the
library and spec disagree the spec wins; the library's source comments
flag every deliberate deviation and the reasoning behind it.

## Credits

The reverse-engineered `.TDF` specification is the work of Roy/SAC,
originally published at
<https://www.roysac.com/blog/2014/04/thedraw-fonts-file-tdf-specifications/>.
SwiftTDF treats that document as the source of truth.

## License

MIT. See [LICENSE](LICENSE).
