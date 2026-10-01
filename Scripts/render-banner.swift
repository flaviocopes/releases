#!/usr/bin/env swift
// Renders the README banner, docs/banner.png, at 2x: the icon, the name, a tagline and
// feature chips on the left, the real window on the right.
// The window is docs/screenshot-dark.png, made by Scripts/screenshot.sh.
// Usage: swift Scripts/render-banner.swift

import AppKit
import SwiftUI

let name = "Releases"
let tagline = "Every release of your Mac apps,\nand the ones you haven't shipped."
let chips = ["Latest releases", "On This Mac", "A CLI for agents"]
let size = CGSize(width: 1280, height: 560)
// Where the window's top-left corner sits, and how much it's scaled down.
let windowOrigin = CGPoint(x: 580, y: 75)
let windowScale: CGFloat = 0.54

// The app icon's green, a bit deeper.
let backgroundTop = Color(hex: 0x0F7A5E)
let backgroundBottom = Color(hex: 0x032E24)
let glow = Color(hex: 0x2BD49C)
let muted = Color.white.opacity(0.74)

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSource = root.appending(path: "Assets/AppIcon.png")
let screenshot = root.appending(path: "docs/screenshot-dark.png")
let output = root.appending(path: "docs/banner.png")
// Scripts/screenshot.sh leaves a 48pt margin around the window for its shadow.
let shadowMargin: CGFloat = 48

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

struct Banner: View {
  let icon: NSImage
  let window: NSImage

  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
      RadialGradient(colors: [glow.opacity(0.45), glow.opacity(0)], center: UnitPoint(x: 0.16, y: 0.36), startRadius: 0, endRadius: 420)

      // The screenshot is 2x, so its size in points is half its pixels.
      Image(nsImage: window)
        .resizable()
        .interpolation(.high)
        .frame(width: CGFloat(window.representations[0].pixelsWide) / 2 * windowScale, height: CGFloat(window.representations[0].pixelsHigh) / 2 * windowScale)
        .offset(x: windowOrigin.x - shadowMargin * windowScale, y: windowOrigin.y - shadowMargin * windowScale)

      VStack(alignment: .leading, spacing: 0) {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .frame(width: 132, height: 132)
          .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        Text(name)
          .font(.system(size: 76, weight: .bold))
          .tracking(-1.8)
          .foregroundStyle(.white)
          .padding(.top, 26)
        Text(tagline)
          .font(.system(size: 27, weight: .regular))
          .lineSpacing(4)
          .foregroundStyle(muted)
          .padding(.top, 8)
        HStack(spacing: 10) {
          ForEach(chips, id: \.self) { chip in
            Text(chip)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white.opacity(0.9))
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(.white.opacity(0.1), in: .capsule)
              .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
          }
        }
        .padding(.top, 26)
      }
      .offset(x: 84, y: 78)
    }
    .frame(width: size.width, height: size.height)
    .clipShape(.rect(cornerRadius: 28))
  }
}

MainActor.assumeIsolated {
  let renderer = ImageRenderer(content: Banner(icon: NSImage(contentsOf: iconSource)!, window: NSImage(contentsOf: screenshot)!))
  renderer.scale = 2
  // ImageRenderer produces 16 bits per channel. Redraw at 8 bits for a small PNG.
  let image = renderer.cgImage!
  let context = CGContext(
    data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
  try! rep.representation(using: .png, properties: [:])!.write(to: output)
  print("Wrote \(output.path)")
}
