// Draws the app icon: a rounded square with a bar chart, one bar red.
import AppKit
let out = CommandLine.arguments[1]
for (px, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
  let s = CGFloat(px)
  let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
    let inset = s * 0.1, r = NSRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    NSColor(red: 0.11, green: 0.14, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225).fill()
    let heights: [CGFloat] = [0.35, 0.55, 0.8, 0.45]
    let bw = r.width * 0.12, gap = r.width * 0.07, total = 4*bw + 3*gap
    for (i, h) in heights.enumerated() {
      (i == 2 ? NSColor(red: 0.82, green: 0.23, blue: 0.23, alpha: 1) : NSColor(red: 0.05, green: 0.64, blue: 0.05, alpha: 1)).setFill()
      let b = NSRect(x: r.midX - total/2 + CGFloat(i)*(bw+gap), y: r.minY + r.height*0.2, width: bw, height: r.height*0.6*h)
      NSBezierPath(roundedRect: b, xRadius: bw*0.3, yRadius: bw*0.3).fill()
    }
    return true
  }
  let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
