// Reproducible export of Salini's app icon and tab-bar glyphs from their vector originals.
//
//   cd ios && swift tools/export_brand_assets.swift
//
// Sources (never redrawn by hand):
// - Salini/Resources/salini-logo.svg — the official wordmark from salini-srl.com.
// - design/icons/soft/*.svg — the «Soft» pack by Gregor Cresnar (Noun Project Pro), copied
//   read-only from BalanceOS with provenance in design/icons/soft/PROVENANCE.json.
//
// Outputs:
// - Salini/Assets.xcassets/AppIcon.appiconset: light (porcelain ground, graphite wordmark),
//   dark (graphite ground, porcelain wordmark) and tinted (grayscale) 1024 px opaque PNGs.
// - Salini/Assets.xcassets/Tab*.imageset: single-scale vector PDF template images.
//
// Only absolute/relative M L H V C S Q T Z path commands are supported — exactly what these
// files use. Anything else stops the export instead of drawing a wrong shape.
import AppKit
import CoreGraphics
import Foundation

struct SVGShape {
  let viewBox: CGRect
  let path: CGPath
}

enum SVGError: Error { case unsupported(String), malformed(String) }

func parseSVG(_ url: URL) throws -> SVGShape {
  let text = try String(contentsOf: url, encoding: .utf8)
  func attribute(_ name: String, in tag: Substring) -> String? {
    guard let r = tag.range(of: " \(name)=\"") else { return nil }
    let rest = tag[r.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    return String(rest[..<end])
  }
  guard let svgOpen = text.range(of: "<svg"), let svgClose = text[svgOpen.upperBound...].firstIndex(of: ">") else {
    throw SVGError.malformed("no <svg>")
  }
  let svgTag = text[svgOpen.lowerBound..<svgClose]
  guard let vb = attribute("viewBox", in: svgTag)?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap({ Double($0) }),
    vb.count == 4
  else { throw SVGError.malformed("viewBox") }
  for unsupported in ["<circle", "<rect", "<ellipse", "<polygon", "<line", "<g ", "transform=", "<use", "<image"] where text.contains(unsupported) {
    throw SVGError.unsupported(unsupported)
  }
  let path = CGMutablePath()
  var search = text[...]
  while let open = search.range(of: "<path") {
    guard let close = search[open.upperBound...].firstIndex(of: ">") else { break }
    let tag = search[open.lowerBound..<close]
    if let d = attribute("d", in: tag) { try appendPath(d, to: path) }
    search = search[close...]
  }
  return SVGShape(viewBox: CGRect(x: vb[0], y: vb[1], width: vb[2], height: vb[3]), path: path)
}

func appendPath(_ d: String, to path: CGMutablePath) throws {
  // Tokenise into commands and numbers (handles «-», «.5.5», exponents).
  var tokens: [String] = []
  var number = ""
  func flush() {
    if !number.isEmpty { tokens.append(number); number = "" }
  }
  for ch in d {
    if ch.isLetter && ch != "e" && ch != "E" {
      flush(); tokens.append(String(ch))
    } else if ch == "-" {
      if let last = number.last, last == "e" || last == "E" { number.append(ch) } else { flush(); number.append(ch) }
    } else if ch == "." {
      if number.contains(".") && !number.contains("e") { flush() }
      number.append(ch)
    } else if ch.isNumber || ch == "e" || ch == "E" {
      number.append(ch)
    } else {
      flush()
    }
  }
  flush()
  var i = 0
  var command: Character = "M"
  var current = CGPoint.zero, start = CGPoint.zero
  var lastControl: CGPoint?
  var lastQuad: CGPoint?
  func num() throws -> CGFloat {
    guard i < tokens.count, let v = Double(tokens[i]) else { throw SVGError.malformed("number at \(i)") }
    i += 1
    return CGFloat(v)
  }
  while i < tokens.count {
    if let c = tokens[i].first, c.isLetter {
      command = c
      i += 1
      if c == "z" || c == "Z" {
        path.closeSubpath(); current = start; lastControl = nil; lastQuad = nil
        continue
      }
    }
    let rel = command.isLowercase
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y) }
    switch command.uppercased().first! {
    case "M":
      let p = pt(try num(), try num())
      path.move(to: p); current = p; start = p
      command = rel ? "l" : "L"  // following pairs are implicit line-tos
      lastControl = nil; lastQuad = nil
    case "L":
      let p = pt(try num(), try num())
      path.addLine(to: p); current = p; lastControl = nil; lastQuad = nil
    case "H":
      let x = try num()
      let p = CGPoint(x: rel ? current.x + x : x, y: current.y)
      path.addLine(to: p); current = p; lastControl = nil; lastQuad = nil
    case "V":
      let y = try num()
      let p = CGPoint(x: current.x, y: rel ? current.y + y : y)
      path.addLine(to: p); current = p; lastControl = nil; lastQuad = nil
    case "C":
      let c1 = pt(try num(), try num()), c2 = pt(try num(), try num()), p = pt(try num(), try num())
      path.addCurve(to: p, control1: c1, control2: c2); current = p; lastControl = c2; lastQuad = nil
    case "S":
      let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
      let c2 = pt(try num(), try num()), p = pt(try num(), try num())
      path.addCurve(to: p, control1: c1, control2: c2); current = p; lastControl = c2; lastQuad = nil
    case "Q":
      let c = pt(try num(), try num()), p = pt(try num(), try num())
      path.addQuadCurve(to: p, control: c); current = p; lastQuad = c; lastControl = nil
    case "T":
      let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
      let p = pt(try num(), try num())
      path.addQuadCurve(to: p, control: c); current = p; lastQuad = c; lastControl = nil
    default:
      throw SVGError.unsupported("path command \(command)")
    }
  }
}

/// Draws a shape into `rect` (top-left origin space), keeping its aspect ratio.
func draw(_ shape: SVGShape, in ctx: CGContext, rect: CGRect, colour: CGColor, flipped: Bool) {
  let scale = min(rect.width / shape.viewBox.width, rect.height / shape.viewBox.height)
  let w = shape.viewBox.width * scale, h = shape.viewBox.height * scale
  ctx.saveGState()
  if flipped {
    // CoreGraphics bitmap/PDF space has y up; SVG has y down.
    ctx.translateBy(x: rect.midX - w / 2, y: rect.midY + h / 2)
    ctx.scaleBy(x: scale, y: -scale)
  } else {
    ctx.translateBy(x: rect.midX - w / 2, y: rect.midY - h / 2)
    ctx.scaleBy(x: scale, y: scale)
  }
  ctx.translateBy(x: -shape.viewBox.minX, y: -shape.viewBox.minY)
  ctx.addPath(shape.path)
  ctx.setFillColor(colour)
  ctx.fillPath(using: .winding)
  ctx.restoreGState()
}

/// The tight bounds of the drawn shape, in its own coordinates — used to centre optically.
func inkBounds(_ shape: SVGShape) -> CGRect { shape.path.boundingBoxOfPath }

func rgb(_ hex: UInt32) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func writeIcon(_ logo: SVGShape, ground: CGColor, ink: CGColor, to url: URL) throws {
  let side = 1024
  guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  else { throw SVGError.malformed("context") }
  ctx.setFillColor(ground)
  ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
  // The wordmark's own ink bounds (not the padded viewBox) span 66 % of the width, centred.
  let bounds = inkBounds(logo)
  let cropped = SVGShape(viewBox: bounds, path: logo.path)
  let width: CGFloat = 676
  let height = width * bounds.height / bounds.width
  ctx.setShouldAntialias(true)
  draw(cropped, in: ctx, rect: CGRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height),
       colour: ink, flipped: true)
  guard let image = ctx.makeImage() else { throw SVGError.malformed("image") }
  let rep = NSBitmapImageRep(cgImage: image)
  try rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// A vector PDF template glyph: black on transparent, sized in points.
func writeGlyphPDF(_ shape: SVGShape, size: CGSize, padding: CGFloat, cropToInk: Bool, to url: URL) throws {
  var box = CGRect(origin: .zero, size: size)
  guard let consumer = CGDataConsumer(url: url as CFURL), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
    throw SVGError.malformed("pdf")
  }
  ctx.beginPDFPage(nil)
  let source = cropToInk ? SVGShape(viewBox: inkBounds(shape), path: shape.path) : shape
  draw(source, in: ctx, rect: box.insetBy(dx: padding, dy: padding), colour: rgb(0), flipped: true)
  ctx.endPDFPage()
  ctx.closePDF()
}

func writeImageSet(_ name: String, folder: URL) throws {
  let json = """
    {
      "images" : [ { "filename" : "\(name).pdf", "idiom" : "universal" } ],
      "info" : { "author" : "tools/export_brand_assets.swift", "version" : 1 },
      "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
    }
    """
  try json.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Salini/Assets.xcassets")
let fm = FileManager.default

// MARK: App icon
let logo = try parseSVG(root.appendingPathComponent("Salini/Resources/salini-logo.svg"))
let iconFolder = assets.appendingPathComponent("AppIcon.appiconset")
try fm.createDirectory(at: iconFolder, withIntermediateDirectories: true)
/// Porcelain ground and graphite wordmark (the app's own paper/ink family), and the reverse.
let porcelain = rgb(0xF3F2EE), graphite = rgb(0x1E2125)
try writeIcon(logo, ground: porcelain, ink: graphite, to: iconFolder.appendingPathComponent("AppIcon.png"))
try writeIcon(logo, ground: rgb(0x16181B), ink: porcelain, to: iconFolder.appendingPathComponent("AppIcon-Dark.png"))
try writeIcon(logo, ground: rgb(0x000000), ink: rgb(0xFFFFFF), to: iconFolder.appendingPathComponent("AppIcon-Tinted.png"))
try """
  {
    "images" : [
      { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
      { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
        "filename" : "AppIcon-Dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
      { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
        "filename" : "AppIcon-Tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
    ],
    "info" : { "author" : "tools/export_brand_assets.swift", "version" : 1 }
  }
  """.write(to: iconFolder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// MARK: Tab glyphs
/// Asset name → (source, canvas in points). The wordmark keeps its proportions in a wider slot.
let glyphs: [(String, URL, CGSize, CGFloat, Bool)] = [
  ("TabSalini", root.appendingPathComponent("Salini/Resources/salini-logo.svg"), CGSize(width: 36, height: 25), 1, true),
  ("TabCatalog", root.appendingPathComponent("design/icons/soft/6153990.svg"), CGSize(width: 27, height: 27), 0, false),
  ("TabProject", root.appendingPathComponent("design/icons/soft/6368500.svg"), CGSize(width: 27, height: 27), 0, false),
  ("TabLibrary", root.appendingPathComponent("design/icons/soft/6136662.svg"), CGSize(width: 27, height: 27), 0, false),
  ("TabStock", root.appendingPathComponent("design/icons/soft/6112921.svg"), CGSize(width: 27, height: 27), 0, false),
  ("TabProfile", root.appendingPathComponent("design/icons/soft/6449928.svg"), CGSize(width: 27, height: 27), 0, false),
]
for (name, source, size, padding, crop) in glyphs {
  let shape = try parseSVG(source)
  let folder = assets.appendingPathComponent("\(name).imageset")
  try fm.createDirectory(at: folder, withIntermediateDirectories: true)
  try writeGlyphPDF(shape, size: size, padding: padding, cropToInk: crop, to: folder.appendingPathComponent("\(name).pdf"))
  try writeImageSet(name, folder: folder)
  print("glyph", name, "←", source.lastPathComponent)
}
print("app icon: light, dark, tinted → \(iconFolder.path)")
