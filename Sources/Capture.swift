import AppKit
import ScreenCaptureKit
import Vision

/// What the screen says about where the student is.
struct Detected: Equatable {
    var number: Int?
    var of: Int?
    var module: Int?
    var section: String?
    var timer: String?
    var practiceTest: Int?     // Bluebook names the test on its screens: "SAT Practice 4"
    var reviewPage = false     // Bluebook's "Check Your Work" page or a break: not on a question

    /// Reads the Bluebook bottom bar ("Question 7 of 22") and header ("Section 2, Module 1: Math").
    static func parse(_ text: String) -> Detected {
        var d = Detected()
        func first(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: text).map { String(text[$0]) } }
        }
        // OCR reads 1 as I or l and "of" as 0f or 01.
        func num(_ s: String) -> Int? { Int(s.replacingOccurrences(of: "[Il|]", with: "1", options: .regularExpression)) }
        if let g = first(#"Qu\S{1,3}tion\s+([\dIl|]{1,2})\s*(?:of|0f|o1|01|ol|0l)\s*(\d{1,2})"#) { d.number = num(g[0]); d.of = Int(g[1]) }
        if let g = first(#"Module\s+([\dIl|])\b"#) { d.module = num(g[0]) }
        // The header names the section, but Desmos can cover it; then the pill's total tells (Math 22, R&W 27).
        if text.range(of: "Reading and Writing", options: .caseInsensitive) != nil { d.section = "Reading and Writing" }
        else if first(#"Module\s+\S\s*\S?\s*Math"#) != nil || d.of == 22 { d.section = "Math" }
        else if d.of == 27 { d.section = "Reading and Writing" }
        else if first(#"\bMath\b"#) != nil { d.section = "Math" }
        if let g = first(#"\b(\d{1,2}:\d{2})\b"#) { d.timer = g[0] }
        if let g = first(#"Practice\s+(?:Test\s*)?#?\s*(\d{1,2})\b"#) { d.practiceTest = Int(g[0]) }
        d.reviewPage = d.number == nil && first(#"Check Your Work|This Module Is Over|Do not refresh this page|Remaining Break Time|Practice Test Complete|You're All Finished"#) != nil
        return d
    }
}

enum Capture {
    static var allowed: Bool { CGPreflightScreenCaptureAccess() }

    /// The front app's biggest window (never ours), at most 1568 px on its long edge
    /// (the size Claude reads best), so the same file serves the review screen and the AI.
    static func frontWindow() async -> (image: CGImage, app: String)? {
        guard allowed, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let win = content.windows
                .filter({ $0.owningApplication?.processID == front.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 300 && $0.frame.height > 200 })
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let cfg = SCStreamConfiguration()
        let scale = min(Double(filter.pointPixelScale), 1568 / max(win.frame.width, win.frame.height))
        cfg.width = Int(win.frame.width * scale)
        cfg.height = Int(win.frame.height * scale)
        cfg.showsCursor = false
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { return nil }
        return (img, front.localizedName ?? "")
    }

    /// On-device OCR; returns all lines joined. Fast mode: the bar text is large and clean, and this runs every few seconds.
    static func text(_ image: CGImage) -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .fast
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US"]
        try? VNImageRequestHandler(cgImage: image).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Where `phrase` appears in the image (OCR boxes), as x, y, w, h in 0–1 with a top-left origin.
    /// Matches inside one line, or across several lines when the phrase wraps.
    static func find(_ phrase: String, in image: CGImage) -> [Double]? {
        func norm(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "’", with: "'")
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        }
        let target = norm(phrase)
        guard target.count >= 3 else { return nil }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([req])
        var boxes: [CGRect] = []
        for obs in req.results ?? [] {
            guard let c = obs.topCandidates(1).first else { continue }
            let line = norm(c.string)
            if let r = c.string.range(of: phrase, options: [.caseInsensitive]), let b = try? c.boundingBox(for: r)?.boundingBox {
                boxes = [b]; break
            } else if line.contains(target) {
                boxes = [obs.boundingBox]; break
            } else if line.count >= 4, target.contains(line) {
                boxes.append(obs.boundingBox)
            }
        }
        guard !boxes.isEmpty else { return nil }
        let u = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
        return [u.minX, 1 - u.maxY, u.width, u.height]
    }

    /// Bluebook's header (section, module, timer, Calculator) and its "Question 7 of 22" pill, read carefully.
    /// The fast full-window pass misreads them ("Que5tion 3 0127"); two thin strips cost ~140 ms.
    static func bluebook(_ image: CGImage) -> String {
        let h = image.height / 10, w = image.width
        let strips = [CGRect(x: 0, y: 0, width: w, height: h), CGRect(x: w / 3, y: image.height - h, width: w / 3, height: h)]
        return strips.compactMap { image.cropping(to: $0) }.map { strip in
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: strip).perform([req])
            return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// Where things are on a Bluebook question frame: whether the question navigator popup covers the choices, and
    /// the question pane (unit rect, top-left origin) when something sits beside it (Desmos, or a passage in R&W).
    struct Layout { var covered: Bool; var pane: CGRect? }
    static func layout(_ image: CGImage) -> Layout {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([req])
        let obs = (req.results ?? []).compactMap { o in o.topCandidates(1).first.map { (text: $0.string, box: o.boundingBox) } }
        func top(_ b: CGRect) -> CGFloat { 1 - b.maxY }   // Vision boxes are bottom-left origin
        let all = obs.map(\.text).joined(separator: "\n").lowercased()
        let covered = all.contains("go to review page") || (all.contains("unanswered") && all.contains("for review") && all.contains("current"))
        var pane: CGRect?
        if let mark = obs.first(where: { $0.text.lowercased().contains("mark for review") })?.box, mark.minX > 0.3 {
            let x0 = max(0, mark.minX - 0.045), y0 = max(0, top(mark) - 0.025)
            let bar = obs.filter { $0.text.range(of: #"Qu\S{1,3}tion\s+\d"#, options: .regularExpression) != nil || $0.text == "Next" || $0.text == "Back" }
                .map { top($0.box) }.filter { $0 > 0.7 }.min()
            let y1 = min(1, (bar ?? 0.94) - 0.01)
            if y1 > y0 + 0.2 { pane = CGRect(x: x0, y: y0, width: 1 - x0, height: y1 - y0) }
        }
        return Layout(covered: covered, pane: pane)
    }

    /// Every word on the screen, carefully (for text-only tutors).
    static func read(_ image: CGImage) -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func jpeg(_ image: CGImage) -> Data? {
        // Redrawn into 8-bit sRGB so a picture of an HDR or wide-gamut screen never glows in the review.
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: flat).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
