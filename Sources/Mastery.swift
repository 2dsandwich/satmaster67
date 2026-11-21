import Foundation

/// The one skill model (spec 1.3): every graded question from tests and practice sets, per official domain and skill.
/// Tests count 1.0 a question, practice sets 0.5, flashcard redos not at all; the two newest tests count double.
/// Priority = domain weight × miss rate (R7); mastered = 85%+ over 12+ questions in the last 30 days (product choice).
struct Mastery: Hashable {
    struct Area: Hashable, Identifiable {
        var domain: String
        var skill: String?                  // nil: the whole domain
        var seen = 0, right = 0             // graded questions, unweighted (what "% right" shows)
        var wSeen = 0.0, wRight = 0.0       // weighted by source and recency
        var emSeen = 0.0, emRight = 0.0     // weighted, Easy and Medium questions only (R9)
        var recentSeen = 0, recentRight = 0 // last 30 days
        var priority = 0.0                  // set by `ranking`
        var id: String { skill.map { "\(domain)|\($0)" } ?? domain }
        var name: String { skill ?? domain }
        var short: String { Mastery.short(name) }
        var section: String { Planner.mathDomains.contains(domain) ? Sec.math : Practice.rw }
        var rate: Double? { seen > 0 ? Double(right) / Double(seen) : nil }
        var mastered: Bool { recentSeen >= 12 && Double(recentRight) >= 0.85 * Double(recentSeen) }
    }

    /// Official share of each domain in its section, in percent [CB-RW][CB-M].
    static let weight: [String: Double] = ["Craft and Structure": 28, "Information and Ideas": 26, "Standard English Conventions": 26,
                                           "Expression of Ideas": 20, "Algebra": 35, "Advanced Math": 35,
                                           "Problem-Solving and Data Analysis": 15, "Geometry and Trigonometry": 15]

    /// Readable short names for pills and narrow rows (the full name shows on hover); the rest are short already.
    static func short(_ name: String) -> String { shortNames[name] ?? name }
    private static let shortNames = [
        "Text Structure and Purpose": "Text Structure", "Cross-Text Connections": "Cross-Text", "Central Ideas and Details": "Central Ideas",
        "Command of Evidence: Textual": "Textual Evidence", "Command of Evidence: Quantitative": "Quantitative Evidence",
        "Form, Structure, and Sense": "Form and Sense", "Linear equations in one variable": "One-variable equations",
        "Linear equations in two variables": "Two-variable equations", "Systems of two linear equations in two variables": "Linear systems",
        "Linear inequalities in one or two variables": "Linear inequalities",
        "Nonlinear equations in one variable and systems of equations in two variables": "Nonlinear equations",
        "Ratios, rates, proportional relationships, and units": "Ratios and rates",
        "One-variable data: Distributions and measures of center and spread": "One-variable data",
        "Two-variable data: Models and scatterplots": "Two-variable data", "Probability and conditional probability": "Probability",
        "Inference from sample statistics and margin of error": "Sample statistics",
        "Evaluating statistical claims: Observational studies and experiments": "Statistical claims",
        "Lines, angles, and triangles": "Lines and angles", "Right triangles and trigonometry": "Right triangles",
        "Standard English Conventions": "English Conventions", "Problem-Solving and Data Analysis": "Data Analysis",
        "Geometry and Trigonometry": "Geometry", "Information and Ideas": "Info and Ideas",
    ]

    var domains: [String: Area] = [:]
    var skills: [String: Area] = [:]        // by Area.id

    init() {}

    /// From tests (newest two count double) and submitted practice sets (full in-app tests are already sessions).
    @MainActor init(sessions: [Session], practice: [PracticeSet] = [], today: Date = Clock.now) {
        let recent = Calendar.current.date(byAdding: .day, value: -30, to: today)!
        let newest = Set(sessions.sorted { ($0.end ?? $0.start) > ($1.end ?? $1.start) }.prefix(2).map(\.id))
        func add(_ domain: String, _ skill: String?, _ right: Bool, _ difficulty: String?, _ w: Double, _ when: Date) {
            guard Self.weight[domain] != nil else { return }
            let em = difficulty.map { $0.lowercased().hasPrefix("e") || $0.lowercased().hasPrefix("m") } ?? false
            func bump(_ a: inout Area) {
                a.seen += 1; a.wSeen += w
                if right { a.right += 1; a.wRight += w }
                if em { a.emSeen += w; if right { a.emRight += w } }
                if when >= recent { a.recentSeen += 1; if right { a.recentRight += 1 } }
            }
            bump(&domains[domain, default: Area(domain: domain)])
            if let sk = skill.flatMap({ Practice.skill(named: $0, in: domain)?.name }) { bump(&skills["\(domain)|\(sk)", default: Area(domain: domain, skill: sk)]) }
        }
        for s in sessions {   // a test still running counts too, as before
            let w = newest.contains(s.id) ? 2.0 : 1.0
            for k in s.keys {
                guard let c = s.correct(k), let d = s.topic(k) else { continue }
                let o = s.official?.answers[k], a = s.q[k]?.analysis
                add(d, o?.skill ?? a?.skill, c, o?.difficulty ?? a?.difficulty, w, s.end ?? s.start)
            }
        }
        for p in practice where p.done && !p.full {
            for i in p.order { let q = p.questions[i]; add(q.domain, q.skill, p.right(i), q.difficulty, 0.5, p.date) }
        }
    }

    /// What to drill, highest priority first, mastered ones left out. A domain with skill data is drilled by its skills.
    /// Before any data: domain weights only. High targets (1400+) rank by Easy and Medium misses first (R9).
    /// Focus domains (set by the student or tutor) come first; ties go to Algebra, then Advanced Math (R7).
    func ranking(target: Int = 1400, focus: [String] = []) -> [Area] {
        let all = domains.values.reduce((0.0, 0.0)) { ($0.0 + $1.wSeen, $0.1 + $1.wRight) }
        let base = all.0 > 0 ? 1 - all.1 / all.0 : 1   // miss rate for an area with no data
        var units: [Area] = []
        for d in Planner.rwDomains + Planner.mathDomains {
            let sk = skills.values.filter { $0.domain == d }
            units += sk.isEmpty ? [domains[d] ?? Area(domain: d)] : sk
        }
        func miss(_ a: Area) -> Double {
            let (s, r) = target >= 1400 && a.emSeen > 0 ? (a.emSeen, a.emRight) : (a.wSeen, a.wRight)
            return (s - r + 2 * base) / (s + 2)   // two pseudo-questions at the overall rate keep 1-of-1 from topping the list
        }
        let tie = ["Algebra": 0, "Advanced Math": 1]
        return units.filter { !$0.mastered }.map { var a = $0; a.priority = (Self.weight[a.domain] ?? 0) * miss(a); return a }
            .sorted { (focus.contains($0.domain) ? 0 : 1, -$0.priority, tie[$0.domain] ?? 2, $0.name) < (focus.contains($1.domain) ? 0 : 1, -$1.priority, tie[$1.domain] ?? 2, $1.name) }
    }

    /// The priorities: the one list Today, Plan, Tutor, the suggestions and the drills use. The top 4 by rank, two per
    /// section so the drills interleave R&W and Math (R10); a focus set, or a section short of missed skills, takes the rank as it is.
    func priorities(target: Int = 1400, focus: [String] = []) -> [Area] {
        // Areas with a miss (or no data yet) come first: a skill answered all right is never picked over one with misses.
        let all = ranking(target: target, focus: focus), open = all.filter { $0.seen == 0 || $0.right < $0.seen }
        let r = open + all.filter { $0.seen > 0 && $0.right == $0.seen }
        var pick = Set(focus.isEmpty ? [Practice.rw, Sec.math].flatMap { s in open.filter { $0.section == s }.prefix(2).map(\.id) } : [])
        for a in r where pick.count < 4 { pick.insert(a.id) }
        return r.filter { pick.contains($0.id) }
    }

    /// Skills (or domains) at 85%+ lately: out of the drills, shown on the Plan.
    /// One level per domain, as `ranking` drills it: its skills when it has skill data, else the whole domain.
    var mastered: [Area] {
        (skills.values.filter(\.mastered) + domains.values.filter { d in d.mastered && !skills.values.contains { $0.domain == d.domain } }).sorted { $0.id < $1.id }
    }

    /// Accuracy by domain, weakest first (ties by name), domains with 2+ graded questions.
    var weakest: [Area] { domains.values.filter { $0.seen >= 2 }.sorted { ($0.rate!, $0.domain) < ($1.rate!, $1.domain) } }

    /// The Question Bank band one above the current accuracy (R8): under 50% Easy and Medium, 50–75% Medium and Hard, above that Hard.
    static func band(_ rate: Double?) -> [String] {
        guard let r = rate else { return ["Medium"] }
        return r < 0.5 ? ["Easy", "Medium"] : r <= 0.75 ? ["Medium", "Hard"] : ["Hard"]
    }
}
