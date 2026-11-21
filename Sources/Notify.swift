import AppKit
@preconcurrency import UserNotifications

/// One local notification to schedule.
struct Reminder: Hashable { var id: String; var date: Date; var title: String; var body: String }

/// Local notifications (spec 3): study days at the student's time, the eve of a full test, sittings, new suggestions.
/// The next 7 days are kept scheduled, rebuilt whenever the plan changes. Under SAT_DATA nothing reaches the system.
@MainActor enum Notifier {
    static let prefix = "sat."
    private(set) static var scheduled: [Reminder] = []
    static let offline = ProcessInfo.processInfo.environment["SAT_DATA"] != nil

    /// What should be scheduled from `now`: pure, so the self-test checks it.
    static func requests(_ p: Profile, days: [StudyDay], suggestions: [Suggestion], now: Date) -> [Reminder] {
        guard p.reminders else { return [] }
        let cal = Calendar.current, today = cal.startOfDay(for: now), horizon = cal.date(byAdding: .day, value: 7, to: today)!
        func at(_ d: Date, _ minutes: Int) -> Date { cal.date(byAdding: .minute, value: minutes, to: cal.startOfDay(for: d))! }
        let fmt: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }
        var out: [Reminder] = []
        let study = days.filter { $0.date >= today && $0.date < horizon && $0.tasks.contains { $0.kind != .rest } }
        for d in study {
            let key = Planner.day.string(from: d.date), when = at(d.date, p.remindAt)
            let tomorrow = cal.date(byAdding: .day, value: 1, to: d.date)!
            // The eve of a full test: that replaces the daily line.
            if let t = days.first(where: { cal.isDate($0.date, inSameDayAs: tomorrow) })?.tasks.first(where: { $0.kind == .test }) {
                out.append(Reminder(id: prefix + "study." + key, date: when, title: "Tomorrow: \(t.title)",
                                    body: "Full test \(t.target == .appTest ? "in the app" : "in Bluebook"), about 2 h 15."))
                continue
            }
            let open = d.tasks.filter { !$0.done && $0.kind != .rest }
            guard !open.isEmpty else { continue }   // quiet once the session is done
            let body = open.map(\.line) + ["\(open.reduce(0) { $0 + $1.minutes }) min"]
            out.append(Reminder(id: prefix + "study." + key, date: when, title: "Today's session", body: body.joined(separator: " · ")))
        }
        for s in p.sittings where s.booked {
            let day = cal.startOfDay(for: s.date)
            if p.nextSitting(now)?.id == s.id {
                out.append(Reminder(id: prefix + "eve." + s.id, date: at(cal.date(byAdding: .day, value: -1, to: day)!, 19 * 60), title: "SAT tomorrow",
                                    body: "Admission ticket, photo ID, charged device. Early night."))
            }
            guard s.total == nil else { continue }
            let next = p.goal(cal.date(byAdding: .day, value: 1, to: day)!).date
            out.append(Reminder(id: prefix + "after." + s.id, date: at(cal.date(byAdding: .day, value: 1, to: day)!, 9 * 60), title: "How did your SAT go?",
                                body: "Your plan now points at \(fmt(next)). Add your score when it's out."))
            if let z = s.snoozedUntil {
                out.append(Reminder(id: prefix + "score." + s.id, date: at(z, 9 * 60), title: "Is your \(fmt(s.date)) score out?", body: "Add it to update your plan."))
            }
        }
        // A new suggestion, at the next study-day reminder.
        if let first = study.map({ at($0.date, p.remindAt) }).first(where: { $0 > now }) {
            for s in suggestions where s.state == .pending && s.kind == .change {
                out.append(Reminder(id: prefix + "suggestion." + s.id, date: first, title: "Plan change", body: "\(s.title) \(s.why)"))
            }
        }
        return out.filter { $0.date > now && $0.date < horizon }.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    /// Replaces every pending reminder of ours with `list`. Test runs (SAT_DATA) only record it.
    static func schedule(_ list: [Reminder]) {
        guard list != scheduled else { return }
        scheduled = list
        guard !offline else { return }
        let center = UNUserNotificationCenter.current(), prefix = prefix
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            for r in list {
                let c = UNMutableNotificationContent()
                c.title = r.title; c.body = r.body; c.userInfo = ["nav": "today"]
                let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.date)
                center.add(UNNotificationRequest(identifier: r.id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
            }
        }
    }

    /// Asks macOS once; false when denied (Settings then offers System Settings). Never asks under SAT_DATA.
    static func permission() async -> Bool {
        guard !offline else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Clicking a reminder opens Today.
    static func install() {
        guard !offline else { return }
        UNUserNotificationCenter.current().delegate = Delegate.shared
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        static let shared = Delegate()
        func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
            await MainActor.run { AppDelegate.shared?.showMain(.today) }
        }
    }
}
