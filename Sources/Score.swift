import SwiftUI

/// The student's official SAT score for a test, typed in from their score report. Only the two section scores are
/// asked for: the total is always their sum, so it can't be entered wrong.
struct ScoreSheet: View {
    let sid: String
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var rw = ""
    @State private var math = ""

    /// A section score as typed: 200–800 in steps of 10, or a plain-language reason it isn't.
    static func section(_ text: String) -> (value: Int?, problem: String?) {
        // Full-width digits from a Japanese input mode count as digits.
        let t = (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text).trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return (nil, nil) }
        guard let v = Int(t) else { return (nil, "Use numbers only.") }
        guard (200...800).contains(v) else { return (nil, "Section scores run from 200 to 800.") }
        guard v % 10 == 0 else { return (nil, "Section scores go up in steps of 10.") }
        return (v, nil)
    }

    var body: some View {
        let a = Self.section(rw), b = Self.section(math)
        let total = a.value.flatMap { x in b.value.map { x + $0 } }
        VStack(alignment: .leading, spacing: L.gap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your SAT score").font(T.section)
                Text(store.session(sid)?.title ?? "").font(T.body).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: L.gap) {
                field(Sec.name("Reading and Writing"), color: Sec.color("Reading and Writing"), text: $rw)
                Text("+").font(T.value).foregroundStyle(.tertiary).padding(.bottom, 8)
                field("Math", color: Sec.color(Sec.math), text: $math)
                Text("=").font(T.value).foregroundStyle(.tertiary).padding(.bottom, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Total").font(T.caption).foregroundStyle(.secondary)
                    Text(total.map(String.init) ?? "–").font(T.big).monospacedDigit().frame(height: 40, alignment: .leading)
                }
            }
            if let p = a.problem ?? b.problem {
                Label(p, systemImage: "exclamationmark.triangle.fill").font(T.body).foregroundStyle(Palette.wrong)
            }
            HStack {
                Spacer()
                if store.session(sid)?.official?.total != nil {
                    Button("Remove Score", role: .destructive) { save(nil, nil) }
                }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(a.value, b.value) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(total == nil)
            }
        }
        .padding(L.inset)
        .frame(width: 600)
        .onAppear {
            let o = store.session(sid)?.official
            rw = o?.readingWriting.map(String.init) ?? ""
            math = o?.math.map(String.init) ?? ""
        }
    }

    private func field(_ title: String, color: Color, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(T.caption).foregroundStyle(color).lineLimit(1).fixedSize()
            TextField("", text: text, prompt: Text("–"))
                .textFieldStyle(.plain).font(T.big).monospacedDigit()
                .frame(width: 150, height: 40)
                .padding(.horizontal, 10)
                .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        }
    }

    private func save(_ rw: Int?, _ math: Int?) {
        store.update(sid) { s in
            var o = s.official ?? Official()
            o.readingWriting = rw; o.math = math
            o.total = rw.flatMap { a in math.map { a + $0 } }
            s.official = o.answers.isEmpty && o.total == nil ? nil : o   // nothing left: back to no official record
        }
        dismiss()
    }
}
