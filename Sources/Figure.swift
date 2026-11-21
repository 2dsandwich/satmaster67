import Charts
import SwiftUI

/// A graph or table in a question, read back from the text Khan Academy puts in its place:
///   "Bar graph titled …. The horizontal axis is labeled …. The vertical axis is labeled …. It ranges from 0 to 700 in increments of 100."
///   then the bars ("* Zinc"), each category ("Without kanamycin:") with its values ("* Zinc: 390"), and MathJax's
///   copy of the axis ticks, one "\[0\]" line each. Line graphs and scatterplots list "* x: y" or "* (x, y)" under each line.
/// A copied table arrives as tab-separated rows. The stored text is never changed here: the tutor reads Khan's words.
struct Figure: Equatable {
    enum Kind: String { case bar, line, scatter, table }
    struct Datum: Equatable { var group: String?; var name: String; var value: Double }
    var kind: Kind
    var title: String?
    var x: String?, y: String?
    var yScale: [Double]?   // from, to, step
    var xScale: [Double]?   // the same for a numeric horizontal axis
    var data: [Datum] = []    // bar: group = category on the x axis, name = bar; line/scatter: group = line, name = x
    var rows: [[String]] = []  // a table, header first

    /// The series in the order the text gives them: bars for a bar graph, lines otherwise.
    var series: [String] {
        var seen: [String] = []
        for d in data { if let s = kind == .bar ? (d.group == nil ? nil : d.name) : d.group, !seen.contains(s) { seen.append(s) } }
        return seen
    }

    /// The figure (nil when the text has none or one this can't draw), the lines it came from, and the rest of the text.
    /// Axis tick lines are dropped from the text either way.
    static func split(_ s: String) -> (figure: Figure?, source: String, text: String) {
        let lines = s.components(separatedBy: .newlines), dropped = ticks(lines)
        var f: Figure?, used = IndexSet()
        if let start = lines.firstIndex(where: { $0.contains(header) }) {
            var g = Figure(kind: .bar), group: String?, i = start
            let kind = lines[start].firstMatch(of: header)!.1.lowercased()
            g.kind = kind.hasPrefix("line") ? .line : kind.hasPrefix("scatter") ? .scatter : kind == "table" ? .table : .bar
            while i < lines.count {
                if dropped.contains(i) { i += 1; continue }
                let l = lines[i], next = i + 1 < lines.count ? lines[i + 1] : ""
                // Once values have started, only a lead-in ("The data for the 2 lines are as follows:") is description; a sentence is the passage.
                if i == start || l.contains(sentence) && (g.data.isEmpty || l.hasSuffix(":")) { g.describe(l) }
                else if let b = l.firstMatch(of: bullet) {
                    let item = String(b.1)
                    if let p = item.wholeMatch(of: point), let x = num(p.1), let y = num(p.2) { g.data.append(.init(group: group, name: fmt(x), value: y)) }
                    else if let p = item.wholeMatch(of: pair), let v = num(p.2) { g.data.append(.init(group: group, name: String(p.1), value: v)) }
                } else if l.hasSuffix(":"), next.contains(bullet) { group = String(l.dropLast()) }
                else { break }
                used.insert(i); i += 1
            }
            if g.kind == .scatter, g.data.contains(where: { num($0.name) == nil }) { g.data = [] }
            // A described trend ("from approximately (0, 10) to (5, 0)") is not data: no chart is drawn from it; a pasted picture shows it.
            if g.kind == .table, g.title != nil { f = g; used = [start] }   // its rows are the tab-separated lines below
            else if g.kind != .table, !g.data.isEmpty { f = g }
            else { used = [] }
        }
        // A copied table: two or more tab-separated rows.
        if f == nil || f!.kind == .table, let r = lines.firstIndex(where: { $0.contains("\t") }) {
            var end = r
            while end < lines.count, lines[end].contains("\t") { end += 1 }
            if end - r >= 2 {
                if f == nil { f = Figure(kind: .table) }
                f!.rows = lines[r..<end].map { $0.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) } }
                used.insert(integersIn: r..<end)
            }
        }
        if f?.kind == .table, f!.rows.isEmpty { f = nil; used = [] }
        used.formUnion(dropped)
        let source = used.map { lines[$0] }.joined(separator: "\n")
        let text = lines.indices.filter { !used.contains($0) }.map { lines[$0] }.joined(separator: "\n")
        return (f, source, text)
    }

    /// A figure the text can't rebuild: only its tick labels came through (a plotted curve, a dot plot), so the student
    /// pastes a picture of it.
    static func pictured(_ s: String?) -> Bool {
        guard let s else { return false }
        let f = split(s).figure
        return f == nil && !ticks(s.components(separatedBy: .newlines)).isEmpty
    }

    /// The axis tick labels a graph leaves behind, one per line: MathJax's "\[0\]" … "\[700\]" (or "$0$" once the Khan reader
    /// has turned the delimiters into the app's) under a description of the axes, and any run of three or more lines that are
    /// only a number or a lone x, y or O (the labels of a picture of a graph).
    static func ticks(_ lines: [String]) -> IndexSet {
        let axis = lines.contains { $0.contains(#/axis is labeled|ranges from/#) }
        let kind = lines.map { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            return t.contains(tick) ? 2 : t.contains(bare) ? 1 : 0
        }
        var out = IndexSet(), i = 0
        while i < lines.count {
            var j = i
            while j < lines.count, kind[j] > 0 { j += 1 }
            for k in i..<j where j - i >= 3 || axis && kind[k] == 2 { out.insert(k) }
            i = j + 1
        }
        return out
    }

    /// For the Khan reader: drops only the echo under a description of the axes, which says the same in words.
    /// A picture's labels stay, so the tutor and `pictured` still see there was a figure.
    static func clean(_ lines: [String]) -> [String] {
        let axis = lines.contains { $0.contains(#/axis is labeled|ranges from/#) }
        return axis ? lines.filter { !$0.trimmingCharacters(in: .whitespaces).contains(tick) } : lines
    }

    static func clean(_ s: String) -> String { clean(s.components(separatedBy: .newlines)).joined(separator: "\n") }

    private static let header = #/^(?:an? )?(bar graph|line graph|scatterplot|scatter plot|table)\b/#.ignoresCase()
    private static let sentence = #/^(?:The |It |For each |Each |There |\d+ )(?:.*\b(?:axis|ranges|data|shown|categor|bars?|lines?|points?|increments))/#
    private static let bullet = #/^[*•\-]\s+(.+)$/#
    private static let point = #/\(\s*([−\-]?[\d.,]+)\s*,\s*([−\-]?[\d.,]+)\s*\)/#
    private static let pair = #/(.+?):\s*(.+)/#
    private static let bare = #/^(?:[−\-]?\d+(?:\.\d+)?|[xyO])$/#
    private static let tick = #/^(?:\\\[|\$\$|\$|\\\()\s*[−\-]?[\d.,]+%?\s*(?:\\\]|\$\$|\$|\\\))$/#

    static func num(_ s: some StringProtocol) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "−", with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "$% ")))
    }
    private static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }

    /// One description line: its sentences set the title, the axis titles and the vertical axis's range.
    private mutating func describe(_ line: String) {
        var axis = ""
        for s in line.components(separatedBy: ". ").map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }) {
            if title == nil, let m = s.firstMatch(of: #/titled (.+)/#) { title = String(m.1) }
            if let m = s.firstMatch(of: #/(horizontal|vertical|x-|y-)\s?axis is labeled (.+)/#) {
                axis = m.1.hasPrefix("h") || m.1 == "x-" ? "x" : "y"
                if axis == "x" { x = String(m.2) } else { y = String(m.2) }
            }
            if axis != "", let m = s.firstMatch(of: #/ranges from ([−\-]?[\d.,]+) to ([−\-]?[\d.,]+)(?: in increments of ([\d.,]+))?/#),
               let lo = Self.num(m.1), let hi = Self.num(m.2), hi > lo {
                let scale = [lo, hi, m.3.flatMap { Self.num($0) } ?? 0]
                if axis == "x" { xScale = scale } else { yScale = scale }
            }
        }
    }
}

/// A figure drawn like Bluebook's: black on white (white on black in dark mode), the test's serif, title above.
struct FigureView: View {
    let f: Figure
    private let serif = Font.custom("STIX Two Text", size: 13)
    private static let shades: [Double] = [1, 0.4, 0.7, 0.2]

    var body: some View {
        VStack(spacing: 10) {
            if let t = f.title { Practice.serif(t, size: 15).bold().multilineTextAlignment(.center) }
            if f.kind == .table { table } else { chart.frame(height: 250) }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var table: some View {
        let n = f.rows.map(\.count).max() ?? 0
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(f.rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(0..<n, id: \.self) { c in
                        Practice.serif(f.rows[r].indices.contains(c) ? f.rows[r][c] : "", size: 14).bold(r == 0)
                            .frame(maxWidth: .infinity, alignment: c == 0 ? .leading : .center)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .overlay(Rectangle().stroke(Color.primary.opacity(0.7), lineWidth: 0.5))
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(0.5)
    }

    private var chart: some View {
        let series = f.series, values = f.data.map(\.value)
        let lo = f.yScale?[0] ?? min(0, values.min() ?? 0), hi = f.yScale?[1] ?? max(lo + 1, values.max() ?? 1)
        let ticks: [Double]? = f.yScale.flatMap { $0[2] > 0 ? Array(stride(from: lo, through: hi, by: $0[2])) : nil }
        let shades: [Color] = (series.isEmpty ? [0] : Array(series.indices)).map { Color.primary.opacity(Self.shades[$0 % Self.shades.count]) }
        // Lines over months or years read best as evenly spaced categories, labels centred under each point; a scatterplot needs a number line.
        let numericX = f.kind == .scatter, pad: CGFloat = 0
        let xs = f.data.compactMap { Figure.num($0.name) }
        let xlo = f.xScale?[0] ?? xs.min() ?? 0, xhi = max(xlo + 1, f.xScale?[1] ?? xs.max() ?? 1)
        let xticks = f.xScale.flatMap { $0[2] > 0 ? Array(stride(from: xlo, through: xhi, by: $0[2])) : nil }
        let plot = Chart(f.data.indices, id: \.self) { mark(f.data[$0], numericX) }
            .chartForegroundStyleScale(domain: series.isEmpty ? [""] : series, range: shades)
            .chartYScale(domain: lo...hi, range: .plotDimension(padding: pad))
            .chartYAxis {
                if let ticks { AxisMarks(position: .leading, values: ticks) { _ in marks } } else { AxisMarks(position: .leading) { _ in marks } }
            }
            .chartXAxis {
                if numericX, let xticks { AxisMarks(values: xticks) { _ in xmarks } } else { AxisMarks { _ in xmarks } }
            }
        return Group { if numericX { plot.chartXScale(domain: xlo...xhi, range: .plotDimension(padding: pad)) } else { plot } }
            .chartXAxisLabel(position: .bottom, alignment: .center) { Text(f.x ?? "").font(serif).foregroundStyle(Color.primary) }
            .chartYAxisLabel(position: .leading, alignment: .center) { Text(f.y ?? "").font(serif).foregroundStyle(Color.primary) }
            .chartPlotStyle { $0.border(Color.primary.opacity(0.7), width: 0.5) }
            .chartLegend(position: .top, alignment: .center, spacing: 12) { legend(series, shades) }
            .chartLegend(series.count > 1 ? .visible : .hidden)
    }

    private func legend(_ series: [String], _ shades: [Color]) -> some View {
        HStack(spacing: 16) {
            ForEach(series.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(shades[i]).frame(width: 12, height: 12)
                    Text(series[i]).font(serif).foregroundStyle(Color.primary)
                }
            }
        }
    }

    @ChartContentBuilder private func mark(_ d: Figure.Datum, _ numericX: Bool) -> some ChartContent {
        let s = PlottableValue.value("s", f.kind == .bar ? d.name : d.group ?? "")
        switch f.kind {
        case .bar:
            if let g = d.group { BarMark(x: .value("x", g), y: .value("y", d.value)).foregroundStyle(by: s).position(by: s) }
            else { BarMark(x: .value("x", d.name), y: .value("y", d.value)).foregroundStyle(Color.primary) }
        case .line where numericX:
            LineMark(x: .value("x", Figure.num(d.name)!), y: .value("y", d.value)).foregroundStyle(by: s)
            PointMark(x: .value("x", Figure.num(d.name)!), y: .value("y", d.value)).foregroundStyle(by: s).symbol(by: s)
        case .line:
            LineMark(x: .value("x", d.name), y: .value("y", d.value)).foregroundStyle(by: s)
            PointMark(x: .value("x", d.name), y: .value("y", d.value)).foregroundStyle(by: s).symbol(by: s)
        default:
            PointMark(x: .value("x", Figure.num(d.name)!), y: .value("y", d.value)).foregroundStyle(by: s).symbol(by: s)
        }
    }

    @AxisMarkBuilder private var xmarks: some AxisMark {
        AxisTick(length: 5, stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary)
        AxisValueLabel(anchor: .top, collisionResolution: .disabled).font(serif).foregroundStyle(Color.primary)
    }

    @AxisMarkBuilder private var marks: some AxisMark {
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.25))
        AxisTick().foregroundStyle(Color.primary)
        AxisValueLabel().font(serif).foregroundStyle(Color.primary)
    }
}
