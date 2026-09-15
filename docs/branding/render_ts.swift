import Foundation
import CoreGraphics
import ImageIO

// Render the approved TS paths directly, without Quick Look's white canvas.
// The source uses absolute M/L/H/V/C/Z commands and the 660 95 288 288 viewBox.
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let source = try String(contentsOf: sourceURL, encoding: .utf8)
let paths = try NSRegularExpression(pattern: #"<path[^>]*fill="(#[A-Fa-f0-9]{6})"[^>]*d="([^"]+)""#)
let tokenizer = try NSRegularExpression(pattern: #"[MLHVCZ]|[-+]?(?:[0-9]*\.)?[0-9]+"#)
let size = 1024
let context = CGContext(data: nil, width: size, height: size,
                        bitsPerComponent: 8, bytesPerRow: size * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.clear(CGRect(x: 0, y: 0, width: size, height: size))
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: CGFloat(size) / 288, y: -CGFloat(size) / 288)
context.translateBy(x: -660, y: -95)

for match in paths.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
    let hex = String(source[Range(match.range(at: 1), in: source)!].dropFirst())
    let rgb = UInt32(hex, radix: 16)!
    context.setFillColor(red: CGFloat((rgb >> 16) & 255) / 255,
                         green: CGFloat((rgb >> 8) & 255) / 255,
                         blue: CGFloat(rgb & 255) / 255, alpha: 1)
    let data = String(source[Range(match.range(at: 2), in: source)!])
    let tokens = tokenizer.matches(in: data, range: NSRange(data.startIndex..., in: data))
        .map { String(data[Range($0.range, in: data)!]) }
    let path = CGMutablePath()
    var index = 0
    var command = "M"
    var point = CGPoint.zero
    func number() -> CGFloat {
        defer { index += 1 }
        return CGFloat(Double(tokens[index])!)
    }
    while index < tokens.count {
        if ["M", "L", "H", "V", "C", "Z"].contains(tokens[index]) {
            command = tokens[index]
            index += 1
        }
        switch command {
        case "M":
            point = CGPoint(x: number(), y: number())
            path.move(to: point)
            command = "L"
        case "L":
            point = CGPoint(x: number(), y: number())
            path.addLine(to: point)
        case "H":
            point.x = number()
            path.addLine(to: point)
        case "V":
            point.y = number()
            path.addLine(to: point)
        case "C":
            let first = CGPoint(x: number(), y: number())
            let second = CGPoint(x: number(), y: number())
            point = CGPoint(x: number(), y: number())
            path.addCurve(to: point, control1: first, control2: second)
        case "Z": path.closeSubpath()
        default: fatalError("Unsupported path command")
        }
    }
    context.addPath(path)
    context.fillPath()
}

let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
for (x, y) in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)] {
    precondition(pixels[(y * size + x) * 4 + 3] == 0, "Canvas must be transparent")
}
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))
print("Rendered approved TS paths. All four corner pixels have alpha 0.")
