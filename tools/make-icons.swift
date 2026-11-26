// Generates emdi's app icons. Run from the repository root:
//
//     swift tools/make-icons.swift
//
// Writes the default (white) icon into emdi/Assets.xcassets/AppIcon.appiconset and the
// alternate (anthracite) icon to emdi/Resources/AppIcon-Anthracite.icns.
// Design: serif "eMD" followed by an orange text cursor standing for the "I".
// At 32 px and below only "e" and the cursor are drawn, so the icon stays readable.

import AppKit

struct Variant {
    var name: String
    var top: NSColor
    var bottom: NSColor
    var border: NSColor?
    var ink: NSColor
}

let white = Variant(name: "White", top: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                    bottom: NSColor(srgbRed: 0.945, green: 0.937, blue: 0.918, alpha: 1),
                    border: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10),
                    ink: NSColor(srgbRed: 0.122, green: 0.141, blue: 0.188, alpha: 1))
let anthracite = Variant(name: "Anthracite", top: NSColor(srgbRed: 0.165, green: 0.165, blue: 0.180, alpha: 1),
                         bottom: NSColor(srgbRed: 0.106, green: 0.106, blue: 0.118, alpha: 1),
                         border: nil,
                         ink: NSColor(srgbRed: 0.969, green: 0.953, blue: 0.918, alpha: 1))
let caretColor = NSColor(srgbRed: 0.949, green: 0.420, blue: 0.114, alpha: 1)

/// Draws the icon on a 1024 x 1024 canvas (top-left origin), following the macOS icon grid:
/// an 824 x 824 rounded square centered on the canvas, with a soft shadow.
func drawIcon(_ variant: Variant, pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let scale = CGFloat(pixels) / 1024
    cg.scaleBy(x: scale, y: scale)
    // Flip to a top-left origin, and tell AppKit so text is drawn the right way up.
    cg.translateBy(x: 0, y: 1024)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    // Shadow (y is flipped, so a positive offset moves it down on screen).
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    variant.bottom.setFill()
    shape.fill()
    cg.restoreGState()

    // Background: a gentle vertical gradient.
    cg.saveGState()
    shape.addClip()
    NSGradient(starting: variant.top, ending: variant.bottom)!.draw(in: tile, angle: 90)
    cg.restoreGState()
    if let border = variant.border {
        border.setStroke()
        let outline = NSBezierPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
        outline.lineWidth = 3
        outline.stroke()
    }

    // Text and caret.
    let small = pixels <= 32
    let fontSize: CGFloat = small ? 560 : 270
    let font = NSFont(name: "Georgia", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    let text = NSAttributedString(string: small ? "e" : "eMD", attributes: [.font: font, .foregroundColor: variant.ink])
    let textWidth = text.size().width
    let caretWidth: CGFloat = small ? 64 : 38
    let gap: CGFloat = small ? 40 : 22
    let capHeight = font.capHeight
    let caretTop = -capHeight * (small ? 1.25 : 1.12)  // relative to the baseline
    let caretBottom = fontSize * 0.13
    let total = textWidth + gap + caretWidth
    let left = 512 - total / 2
    // Center the caret's height on the tile.
    let baseline = 512 - (caretTop + caretBottom) / 2
    text.draw(at: NSPoint(x: left, y: baseline - font.ascender))
    caretColor.setFill()
    let caret = CGRect(x: left + textWidth + gap, y: baseline + caretTop, width: caretWidth, height: caretBottom - caretTop)
    NSBezierPath(roundedRect: caret, xRadius: caretWidth / 2, yRadius: caretWidth / 2).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// (point size, scale) pairs macOS uses for app icons.
let slots: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                                           (256, 1), (256, 2), (512, 1), (512, 2)]

func fileName(_ slot: (points: Int, scale: Int)) -> String {
    "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)

// Default icon: asset catalog.
let assets = root.appending(path: "emdi/Assets.xcassets")
let appIconSet = assets.appending(path: "AppIcon.appiconset")
try fm.createDirectory(at: appIconSet, withIntermediateDirectories: true)
try #"{ "info" : { "author" : "xcode", "version" : 1 } }"#.write(to: assets.appending(path: "Contents.json"),
                                                                 atomically: true, encoding: .utf8)
var images: [String] = []
for slot in slots {
    try writePNG(drawIcon(white, pixels: slot.points * slot.scale), to: appIconSet.appending(path: fileName(slot)))
    images.append(#"    { "filename" : "\#(fileName(slot))", "idiom" : "mac", "scale" : "\#(slot.scale)x", "size" : "\#(slot.points)x\#(slot.points)" }"#)
}
let contents = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try contents.write(to: appIconSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)

// Alternate icon: .icns built with iconutil.
let resources = root.appending(path: "emdi/Resources")
try fm.createDirectory(at: resources, withIntermediateDirectories: true)
let iconset = fm.temporaryDirectory.appending(path: "AppIcon-Anthracite.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for slot in slots {
    try writePNG(drawIcon(anthracite, pixels: slot.points * slot.scale), to: iconset.appending(path: fileName(slot)))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appending(path: "AppIcon-Anthracite.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Icons written to \(appIconSet.path) and \(resources.path)")
