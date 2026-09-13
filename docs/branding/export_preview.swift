import AppKit
import ImageIO
// Crop the top logo strip from a Quick Look SVG render (pixel coordinates).
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let source = CGImageSourceCreateWithURL(input as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: 400))!
let bitmap = NSBitmapImageRep(cgImage: cropped)
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
