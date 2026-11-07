import AppKit
import CoreGraphics
import Foundation

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let green = NSColor(calibratedRed: 0.29, green: 0.98, blue: 0.10, alpha: 1).cgColor
let white = NSColor.white.cgColor
let black = NSColor(calibratedRed: 0.025, green: 0.026, blue: 0.035, alpha: 1).cgColor
context.setFillColor(black)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

func roundedRect(_ rect: CGRect, radius: CGFloat, color: CGColor) {
    context.setFillColor(color)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}
func polygon(_ points: [CGPoint], color: CGColor) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    for p in points.dropFirst() { context.addLine(to: p) }
    context.closePath()
    context.setFillColor(color)
    context.fillPath()
}
func line(_ points: [CGPoint], width: CGFloat, color: CGColor) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    for p in points.dropFirst() { context.addLine(to: p) }
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

// Green monitor brackets and stand.
line([CGPoint(x: 260,y: 430), CGPoint(x: 170,y: 430), CGPoint(x: 170,y: 770), CGPoint(x: 285,y: 770)], width: 38, color: green)
line([CGPoint(x: 740,y: 770), CGPoint(x: 855,y: 770), CGPoint(x: 855,y: 430), CGPoint(x: 760,y: 430)], width: 38, color: green)
polygon([CGPoint(x: 462,y: 420),CGPoint(x: 562,y: 420),CGPoint(x: 581,y: 372),CGPoint(x: 443,y: 372)], color: green)
roundedRect(CGRect(x: 352,y: 348,width: 320,height: 27), radius: 13, color: green)

// Stylized silver S surrounding a green play triangle.
let sPath = CGMutablePath()
sPath.move(to: CGPoint(x: 712,y: 770))
sPath.addLine(to: CGPoint(x: 452,y: 770))
sPath.addCurve(to: CGPoint(x: 375,y: 648), control1: CGPoint(x: 346,y: 770), control2: CGPoint(x: 340,y: 690))
sPath.addCurve(to: CGPoint(x: 445,y: 598), control1: CGPoint(x: 390,y: 625), control2: CGPoint(x: 420,y: 610))
sPath.move(to: CGPoint(x: 580,y: 600))
sPath.addCurve(to: CGPoint(x: 650,y: 540), control1: CGPoint(x: 685,y: 610), control2: CGPoint(x: 695,y: 558))
sPath.addCurve(to: CGPoint(x: 580,y: 482), control1: CGPoint(x: 645,y: 500), control2: CGPoint(x: 630,y: 482))
sPath.addLine(to: CGPoint(x: 340,y: 482))
context.addPath(sPath)
context.setStrokeColor(white)
context.setLineWidth(79)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()
polygon([CGPoint(x: 475,y: 546),CGPoint(x: 475,y: 681),CGPoint(x: 601,y: 614)], color: green)

// Bottom wordmarks.
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
func drawText(_ text: String, rect: CGRect, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph
    ]
    let ns = NSAttributedString(string: text, attributes: attributes)
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    ns.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}
drawText("▣", rect: CGRect(x: 185,y: 156,width: 220,height: 120),
         font: .systemFont(ofSize: 112, weight: .black), color: .white)
roundedRect(CGRect(x: 485,y: 159,width: 5,height: 100), radius: 2, color: NSColor.gray.cgColor)
drawText("KICK", rect: CGRect(x: 535,y: 165,width: 355,height: 105),
         font: .systemFont(ofSize: 93, weight: .black),
         color: NSColor(cgColor: green) ?? .green)

let image = context.makeImage()!
let bitmap = NSBitmapImageRep(cgImage: image)
let png = bitmap.representation(using: .png, properties: [:])!
let output = CommandLine.arguments[1]
try png.write(to: URL(fileURLWithPath: output))
print("Created StreamHub app icon at \\(output)")
