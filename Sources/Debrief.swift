import ImageIO
import SwiftUI

// MARK: - Pieces shared by the review screens

/// The coach: a graduation cap on an accent-colored disc.
struct CoachFace: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "graduationcap.fill")
            .font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.accentColor.gradient))
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: max(1, size / 28)))
            .accessibilityHidden(true)
    }
}

/// The screenshot cropped to the question itself (no window chrome or empty page), with the deciding phrase
/// highlighted like a marker pen. Size the view with `content(url).aspect` so the crop fills it.
struct ZoomedShot: View {
    let url: URL?
    let box: [Double]?
    var radius = L.inner
    var pane: CGRect? = nil   // a known question pane (Math beside Desmos) replaces the automatic crop

    /// Width over height of what's shown.
    static func aspect(_ url: URL, pane: CGRect?) -> CGFloat {
        guard let p = pane else { return content(url).aspect }
        let full = content(url)   // its rect is in unit space, its aspect in pixels: recover the image's own aspect
        let imgAspect = full.aspect * full.rect.height / max(full.rect.width, 0.001)
        return imgAspect * p.width / max(p.height, 0.001)
    }

    var body: some View {
        GeometryReader { g in
            if let url, let img = Self.image(url) {
                let c = pane ?? Self.content(url).rect
                let crop = CGRect(x: c.minX * img.size.width, y: c.minY * img.size.height, width: c.width * img.size.width, height: c.height * img.size.height)
                let scale = min(g.size.width / crop.width, g.size.height / crop.height)
                Image(nsImage: img).resizable().allowedDynamicRange(.standard)
                    .frame(width: img.size.width * scale, height: img.size.height * scale)
                    .overlay(alignment: .topLeading) {
                        if let b = box {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Rich.ink.opacity(0.32))   // teal, not yellow: Bluebook's own highlights are yellow
                                .frame(width: (b[2] * img.size.width + 12) * scale, height: (b[3] * img.size.height + 8) * scale)
                                .offset(x: (b[0] * img.size.width - 6) * scale, y: (b[1] * img.size.height - 4) * scale)
                                .blendMode(.multiply)
                        }
                    }
                    .offset(x: -crop.minX * scale, y: -crop.minY * scale)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private static var cache: [URL: (rect: CGRect, aspect: CGFloat)] = [:]
    private static let images = NSCache<NSURL, NSImage>()

    /// The picture at `url`, read from disk once (a replaced picture gets a new file name, so the URL is a safe key).
    static func image(_ url: URL) -> NSImage? {
        if let i = images.object(forKey: url as NSURL) { return i }
        guard let i = NSImage(contentsOf: url) else { return nil }
        images.setObject(i, forKey: url as NSURL)
        return i
    }

    /// The printed part of the page, as a unit rect of the image: the longest band of rows whose right edge is white
    /// (the page between Bluebook's header and footer), trimmed to where there is ink. Whole image when nothing is found.
    static func content(_ url: URL) -> (rect: CGRect, aspect: CGFloat) {
        if let c = cache[url] { return c }
        var out = (rect: CGRect(x: 0, y: 0, width: 1, height: 1), aspect: CGFloat(1.6))
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil), img.width > 0 {
            let w = 512, h = max(1, img.height * 512 / img.width)
            var px = [UInt8](repeating: 0, count: w * h)
            let drawn = px.withUnsafeMutableBytes { buf -> Bool in
                guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            out.aspect = CGFloat(img.width) / CGFloat(img.height)
            if drawn {
                let edge = Array(w - w / 100 - 8..<w - w / 100)   // right edge only: the calculator can cover the left
                let page = (0..<h).map { y in edge.filter { px[y * w + $0] > 245 }.count >= edge.count - 2 }
                var best = 0..<0, start = 0
                for y in 0...h where y == h || !page[y] {
                    if y - start > best.count { best = start..<y }
                    start = y + 1
                }
                let rows = best.filter { y in (4...w / 2).contains((0..<w).filter { px[y * w + $0] < 200 }.count) }   // ink, not a solid band
                let cols = (0..<w).filter { x in rows.filter { px[$0 * w + x] < 200 }.count >= 2 }
                if best.count > h / 5, let y0 = rows.first, let y1 = rows.last, let x0 = cols.first, let x1 = cols.last {
                    let pad = 10
                    let r = CGRect(x: max(0, x0 - pad), y: max(0, y0 - pad), width: 0, height: 0)
                    let rect = CGRect(x: r.minX, y: r.minY, width: CGFloat(min(w, x1 + pad + 1)) - r.minX, height: CGFloat(min(h, y1 + pad + 1)) - r.minY)
                    out.rect = CGRect(x: rect.minX / CGFloat(w), y: rect.minY / CGFloat(h), width: rect.width / CGFloat(w), height: rect.height / CGFloat(h))
                    out.aspect = out.rect.width * CGFloat(img.width) / (out.rect.height * CGFloat(img.height))
                }
            }
        }
        cache[url] = out
        return out
    }
}

/// Question chips; opening one passes the chip's own frame (in the "review" space) so the question grows out of it.
struct Chips: View {
    let labels: [(String, String)]   // shown label, question key
    let open: (String, CGRect) -> Void
    var body: some View {
        Flow(spacing: 4) {
            ForEach(labels, id: \.1) { l in Chip(title: l.0) { r in open(l.1, r) } }
        }
    }

    private struct Chip: View {
        let title: String
        let tap: (CGRect) -> Void
        @State private var frame: CGRect = .zero
        var body: some View {
            Button(title) { tap(frame) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).frame(height: 22)
                .background(Color.primary.opacity(0.07), in: Capsule())
                .hoverLift(1.08)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("review")) } action: { frame = $0 }
        }
    }
}

/// Wrapping row layout.
struct Flow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, y: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, y: CGFloat, height: CGFloat)] = []
        var cur: [Int] = [], x: CGFloat = 0, h: CGFloat = 0, y: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if !cur.isEmpty, x + s.width > width {
                rows.append((cur, x - spacing, y, h)); y += h + spacing; cur = []; x = 0; h = 0
            }
            cur.append(i); x += s.width + spacing; h = max(h, s.height)
        }
        if !cur.isEmpty { rows.append((cur, x - spacing, y, h)) }
        return rows
    }
}
