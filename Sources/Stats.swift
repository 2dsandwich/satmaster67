import AppKit

/// The numbers behind the review: one section, or several for the overall view (each keeps its own pace).
struct Stats {
    struct Topic { let name: String; let count: Int; let right: Int; let avg: Double }

    var marked = 0, right = 0, guessed = 0, revisited = 0
    var avgRight: Double?, avgWrong: Double?
    var over: [String] = []
    var topics: [Topic] = []
    var time = 0.0, limit = 0.0       // seconds used, and the official time for the modules taken

    init(_ s: Session) { self.init([s]) }

    init(_ parts: [Session]) {
        var rightT: [Double] = [], wrongT: [Double] = []
        var byTopic: [String: [(Double, Bool)]] = [:]
        for s in parts {
            for k in s.keys {
                let t = s.seconds(k), c = s.correct(k)
                time += t
                if c == true { rightT.append(t) } else if c == false { wrongT.append(t) }
                if t > s.pace { over.append(k) }
                if s.q[k]?.guessed == true { guessed += 1 }
                if s.visitCount(k) > 1 { revisited += 1 }
                if let topic = s.topic(k) { byTopic[topic, default: []].append((t, c == true)) }
            }
            limit += Double(Set(s.visits.map(\.module)).count) * Sec.limit(s.section)
        }
        func avg(_ x: [Double]) -> Double? { x.isEmpty ? nil : x.reduce(0, +) / Double(x.count) }
        right = rightT.count; marked = rightT.count + wrongT.count
        avgRight = avg(rightT); avgWrong = avg(wrongT)
        topics = byTopic.map { Topic(name: $0.key, count: $0.value.count, right: $0.value.filter(\.1).count, avg: avg($0.value.map(\.0))!) }
            .sorted { Double($0.right) / Double($0.count) < Double($1.right) / Double($1.count) }
    }
}

@MainActor enum Export {
    /// questions.csv next to the raw data, then shows it in Finder.
    static func csv(_ s: Session) {
        func q(_ v: String) -> String { "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["section,module,question,seconds,visits,result,guessed,flagged,topic,skill,difficulty,correct_answer,student_answer"]
        for k in s.keys {
            let st = s.q[k] ?? QState(), a = st.analysis, p = k.dropFirst().split(separator: "-")
            rows.append([Session.section(of: k), String(p[0]), String(p[1]), String(format: "%.1f", s.seconds(k)), "\(s.visitCount(k))",
                         resultName(s.correct(k)), "\(st.guessed)", "\(st.flagged)",
                         q(a?.topic ?? ""), q(a?.skill ?? ""), q(a?.difficulty ?? ""), q(a?.correctAnswer ?? ""), q(a?.studentAnswer ?? "")].joined(separator: ","))
        }
        let url = Store.shared.dir(s.id).appendingPathComponent("questions.csv")
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
