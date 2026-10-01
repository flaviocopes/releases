#!/usr/bin/env swift
// Renders the Releases app icon: a shipping box with a version tag hanging from its corner,
// baked into a 1024px squircle on Apple's macOS icon grid. Scripts/build-app.sh turns it into AppIcon.icns.
// Usage: swift Scripts/render-icon.swift Assets/AppIcon.png

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
// Apple's macOS icon grid: an 824pt continuous-corner body centered on a 1024pt canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185.4

// The box, drawn isometric. The top face is a rhombus around (boxCenterX, topFaceCenterY).
let boxCenterX: CGFloat = 432
let topFaceCenterY: CGFloat = 406
let boxHalfWidth: CGFloat = 228
let boxRise: CGFloat = 132
let boxDepth: CGFloat = 236
let boxCornerRadius: CGFloat = 22
let tapeWidth: CGFloat = 74

// The tag hangs from a string tied to the box's right corner.
let tagHole = CGPoint(x: 724, y: 462)
let tagWidth: CGFloat = 146
let tagLength: CGFloat = 238
let tagChamfer: CGFloat = 50
let tagAngle: CGFloat = -11
let holeRadius: CGFloat = 19
let stringWidth: CGFloat = 13

let backgroundTop: UInt32 = 0x2BD49C
let backgroundBottom: UInt32 = 0x08785F
let topFaceColor: UInt32 = 0xFFFFFF
let leftFaceColor: UInt32 = 0xD4F1E5
let rightFaceColor: UInt32 = 0x9AD7C0
let topTapeColor: UInt32 = 0xDDF2EA
let leftTapeColor: UInt32 = 0xB9E5D4
let tagColor: UInt32 = 0xFFC53D
let tagLineColor: UInt32 = 0xE39B12
let stringColor: UInt32 = 0xFFF6DC

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha
  )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
  CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
  RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
}

func roundedPolygon(_ points: [CGPoint], radii: [CGFloat]) -> CGPath {
  let path = CGMutablePath()
  let last = points[points.count - 1]
  path.move(to: CGPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
  for index in points.indices {
    path.addArc(tangent1End: points[index], tangent2End: points[(index + 1) % points.count], radius: radii[index])
  }
  path.closeSubpath()
  return path
}

func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }
func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { (a + b) * 0.5 }
func unit(_ vector: CGPoint) -> CGPoint { vector * (1 / hypot(vector.x, vector.y)) }

// The top face's corners: back, right, front and left.
let back = CGPoint(x: boxCenterX, y: topFaceCenterY - boxRise)
let right = CGPoint(x: boxCenterX + boxHalfWidth, y: topFaceCenterY)
let front = CGPoint(x: boxCenterX, y: topFaceCenterY + boxRise)
let left = CGPoint(x: boxCenterX - boxHalfWidth, y: topFaceCenterY)
let down = CGPoint(x: 0, y: boxDepth)

// One rounded silhouette, with sharp seams between the faces inside it.
func drawBox(_ context: CGContext) {
  let silhouette = roundedPolygon(
    [back, right, right + down, front + down, left + down, left],
    radii: [CGFloat](repeating: boxCornerRadius, count: 6)
  )
  context.saveGState()
  context.addPath(silhouette)
  context.clip()

  let faces: [([CGPoint], UInt32)] = [
    ([left, front, front + down, left + down], leftFaceColor),
    ([front, right, right + down, front + down], rightFaceColor),
    ([back, right, front, left], topFaceColor)
  ]
  for (points, color) in faces {
    context.addLines(between: points)
    context.setFillColor(rgb(color))
    context.fillPath()
  }

  // Tape along the seam of the flaps: across the top, from the back-right edge to the
  // front-left edge, then down the left face.
  let across = unit(right - back) * (tapeWidth / 2)
  let start = midpoint(back, right)
  let end = midpoint(left, front)
  context.addLines(between: [start - across, start + across, end + across, end - across])
  context.setFillColor(rgb(topTapeColor))
  context.fillPath()
  context.addLines(between: [end - across, end + across, end + across + down, end - across + down])
  context.setFillColor(rgb(leftTapeColor))
  context.fillPath()

  context.restoreGState()
}

// A luggage tag with its hole at the origin and its body hanging down.
func drawTag(_ context: CGContext) {
  let top = -holeRadius - 36
  let bottom = top + tagLength
  let half = tagWidth / 2
  let outline = roundedPolygon(
    [
      CGPoint(x: -half + tagChamfer, y: top),
      CGPoint(x: half - tagChamfer, y: top),
      CGPoint(x: half, y: top + tagChamfer),
      CGPoint(x: half, y: bottom),
      CGPoint(x: -half, y: bottom),
      CGPoint(x: -half, y: top + tagChamfer)
    ],
    radii: [14, 14, 18, 30, 30, 18]
  )
  context.addPath(outline)
  context.setFillColor(rgb(tagColor))
  context.fillPath()

  context.setFillColor(rgb(tagLineColor))
  for (offset, width) in [(CGFloat(78), CGFloat(92)), (122, 60)] {
    let line = CGRect(x: -half + 30, y: offset, width: width, height: 22)
    context.addPath(CGPath(roundedRect: line, cornerWidth: 11, cornerHeight: 11, transform: nil))
  }
  context.fillPath()

  context.setBlendMode(.clear)
  context.fillEllipse(in: CGRect(x: -holeRadius, y: -holeRadius, width: 2 * holeRadius, height: 2 * holeRadius))
  context.setBlendMode(.normal)
}

// The artwork, in 1024pt canvas coordinates with a top-left origin.
func drawArtwork(_ context: CGContext, scale: CGFloat) {
  // Shadows ignore the transform: the offset is in unflipped pixels, so scale it by hand.
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -16 * scale), blur: 34 * scale, color: rgb(0x033B2E, 0.4))
  context.beginTransparencyLayer(auxiliaryInfo: nil)
  drawBox(context)
  context.endTransparencyLayer()
  context.restoreGState()

  // The string, from just inside the box's right corner to the tag's hole.
  let knot = right + CGPoint(x: -22, y: 2)
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 22 * scale, color: rgb(0x033B2E, 0.35))
  context.beginTransparencyLayer(auxiliaryInfo: nil)
  context.saveGState()
  context.translateBy(x: tagHole.x, y: tagHole.y)
  context.rotate(by: tagAngle * .pi / 180)
  drawTag(context)
  context.restoreGState()
  context.endTransparencyLayer()
  context.restoreGState()

  context.move(to: knot)
  context.addQuadCurve(to: tagHole, control: CGPoint(x: knot.x + 44, y: knot.y - 30))
  context.setStrokeColor(rgb(stringColor))
  context.setLineWidth(stringWidth)
  context.setLineCap(.round)
  context.strokePath()
}

func drawIcon(_ context: CGContext, scale: CGFloat) {
  let bodyPath = squircle(body, radius: bodyRadius)

  // Drop shadow under the body, as in Apple's icon template.
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 22 * scale, color: rgb(0x000000, 0.32))
  context.addPath(bodyPath)
  context.setFillColor(rgb(backgroundBottom))
  context.fillPath()
  context.restoreGState()

  context.saveGState()
  context.addPath(bodyPath)
  context.clip()
  context.drawLinearGradient(
    gradient([rgb(backgroundTop), rgb(backgroundBottom)]),
    start: CGPoint(x: 0, y: body.minY),
    end: CGPoint(x: 0, y: body.maxY),
    options: []
  )
  drawArtwork(context, scale: scale)
  context.restoreGState()

  // Hairline highlight along the top edge of the body.
  context.saveGState()
  context.addPath(bodyPath)
  context.setLineWidth(3)
  context.replacePathWithStrokedPath()
  context.clip()
  context.drawLinearGradient(
    gradient([rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0)]),
    start: CGPoint(x: 0, y: body.minY),
    end: CGPoint(x: 0, y: body.midY),
    options: []
  )
  context.restoreGState()
}

func render(pixels: Int) -> CGImage {
  let context = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let scale = CGFloat(pixels) / canvas
  context.translateBy(x: 0, y: CGFloat(pixels))
  context.scaleBy(x: scale, y: -scale)
  drawIcon(context, scale: scale)
  return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
}

let output = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets/AppIcon.png")
try! FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
write(render(pixels: 1024), to: output)
print("Wrote \(output.path)")
