import AppKit
import SwiftUI

// MARK: - Chat pieces shared by the question panel and the Tutor page
// Laid out like ChatGPT and Claude: tutor replies as plain full-width text, student turns as bubbles on the right,
// a rounded composer at the bottom with the send arrow inside.

/// The markdown tutors write: paragraphs, "- " bullets, "1. " numbered lists, inline **bold**.
/// AttributedString(markdown:) only does inline syntax, so blocks are split here.
struct ChatText: View {
    enum Block: Equatable { case text(String), bullet(String), number(String, String) }
    let text: String
    var size: CGFloat = 15
    var fill = true                       // false: as wide as its longest line (inside a bubble)

    static func blocks(_ s: String) -> [Block] {
        var out: [Block] = [], gap = true
        for raw in s.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { gap = true; continue }
            defer { gap = false }
            if let r = line.wholeMatch(of: #/[-*•]\s+(.+)/#) { out.append(.bullet(String(r.1))); continue }
            if let r = line.wholeMatch(of: #/(\d{1,3})[.)]\s+(.+)/#) { out.append(.number("\(r.1).", String(r.2))); continue }
            let body = line.wholeMatch(of: #/#{1,6}\s+(.+)/#).map { "**\($0.1)**" } ?? line
            switch out.last {
            case .text(let t)? where !gap: out[out.count - 1] = .text(t + "\n" + body)
            case .bullet(let t)? where !gap && raw.first == " ": out[out.count - 1] = .bullet(t + " " + body)
            case .number(let m, let t)? where !gap && raw.first == " ": out[out.count - 1] = .number(m, t + " " + body)
            default: out.append(.text(body))
            }
        }
        return out
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.6) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, b in
                switch b {
                case .text(let s): QLink.text(s, size: size)   // Rich text, with question labels as links
                case .bullet(let s): item("•", s)
                case .number(let m, let s): item(m, s)
                }
            }
        }
        .font(.system(size: size)).lineSpacing(size * 0.22)
        .textSelection(.enabled)
        .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
    }

    private func item(_ marker: String, _ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: size, alignment: .trailing)
            QLink.text(s, size: size)
        }
        .padding(.leading, 4)
    }
}

/// One turn. The student's text sits in a bubble on the right; the tutor's is plain text with its mark.
struct ChatRow<Extra: View>: View {
    let fromStudent: Bool, text: String
    var size: CGFloat = 15
    var gutter: CGFloat = 80               // keeps student bubbles to about three quarters of the column
    let extra: Extra

    init(fromStudent: Bool, text: String, size: CGFloat = 15, gutter: CGFloat = 80, @ViewBuilder extra: () -> Extra) {
        self.fromStudent = fromStudent; self.text = text; self.size = size; self.gutter = gutter; self.extra = extra()
    }

    var body: some View {
        if fromStudent {
            Text(text).font(.system(size: size)).lineSpacing(size * 0.15).textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.leading, gutter)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack(alignment: .top, spacing: 12) {
                CoachFace(size: 24)
                VStack(alignment: .leading, spacing: 8) {
                    ChatText(text: text, size: size).padding(.top, 2)
                    extra
                }
            }
        }
    }
}

extension ChatRow where Extra == EmptyView {
    init(fromStudent: Bool, text: String, size: CGFloat = 15, gutter: CGFloat = 80) {
        self.init(fromStudent: fromStudent, text: text, size: size, gutter: gutter) { EmptyView() }
    }
}

extension View {
    /// A messenger bubble (onboarding, Tutor page): the tutor's in `fill` on the left, the student's in accent on the right,
    /// lines capped at 520 pt.
    func bubble(mine: Bool = false, fill: Color) -> some View {
        font(.system(size: 15)).foregroundStyle(mine ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(mine ? Color.accentColor : fill, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .frame(maxWidth: 520, alignment: mine ? .trailing : .leading)
    }
}

/// Three dots pulsing in turn while the tutor is typing, sized like a one-line bubble.
struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.secondary).frame(width: 7, height: 7)
                    .opacity(on ? 1 : 0.3).scaleEffect(on ? 1 : 0.7)
                    .animation(.easeInOut(duration: 0.55).repeatForever().delay(Double(i) * 0.18), value: on)
            }
        }
        .padding(.horizontal, 14).frame(height: 35)
        .onAppear { on = true }
        .accessibilityElement().accessibilityLabel("Your tutor is typing")
    }
}

/// The tutor's mark with three pulsing dots, shown until the reply arrives.
struct ChatTyping: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 12) {
            CoachFace(size: 24)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.secondary).frame(width: 7, height: 7)
                        .opacity(on ? 1 : 0.3).scaleEffect(on ? 1 : 0.7)
                        .animation(.easeInOut(duration: 0.55).repeatForever().delay(Double(i) * 0.18), value: on)
                }
            }
        }
        .onAppear { on = true }
        .accessibilityElement().accessibilityLabel("Your tutor is writing")
    }
}

/// A rounded multi-line field with the send arrow inside, and the usual caution under it.
struct Composer: View {
    let placeholder: String
    @Binding var text: String
    var size: CGFloat = 15
    var enabled = true
    var busy = false
    var focus: FocusState<Bool>.Binding
    let send: () -> Void

    var body: some View {
        let canSend = enabled && !busy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: size)).lineLimit(1...6)
                .focused(focus)
                .disabled(!enabled).opacity(enabled ? 1 : 0.6)
                .onSubmit { if canSend { send() } }
                .padding(.vertical, 5)
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(canSend ? Color.accentColor : Color.secondary.opacity(0.35)))
            }
            .buttonStyle(.plain).disabled(!canSend)
            .help("Send")
        }
        .padding(.leading, 14).padding(.trailing, 7).padding(.vertical, 7)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: L.inner, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// Before the first message: the tutor's greeting centred, with ready-made questions under it.
/// The chips sit in a row when they fit and stack when they don't, so none is ever cut off.
struct ChatEmpty: View {
    let greeting: String
    let prompts: [String]
    var size: CGFloat = 15
    var enabled = true
    let pick: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            CoachFace(size: 40)
            Text(greeting).font(.system(size: size + 1)).multilineTextAlignment(.center).frame(maxWidth: 520)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(spacing: 8) { chips }
            }
            .disabled(!enabled)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chips: some View { ForEach(prompts, id: \.self) { p in Chip(p) { pick(p) } } }
}

extension View {
    /// A short thread starts at the top like ChatGPT's; a long one opens on, and follows, the newest message.
    func chatScrollAnchors() -> some View {
        defaultScrollAnchor(.top, for: .alignment).defaultScrollAnchor(.bottom, for: .initialOffset).defaultScrollAnchor(.bottom, for: .sizeChanges)
    }
}

// MARK: - Chat about one question

/// A glass button in the corner that grows into a chat about the question.
struct QuestionChat: View {
    let sid: String, key: String
    var outerRadius: CGFloat = L.radius
    var inset: CGFloat = L.inset
    var open = false
    @ObservedObject var store = Store.shared

    static let prompts = ["Explain it more simply", "Why not my answer?", "A faster way?", "A similar question"]

    var body: some View {
        let st = store.session(sid)?.q[key] ?? QState()
        let ready = st.convo != nil
        ChatBubble(lines: st.chat, busy: store.busy.contains("\(sid)/\(key)/chat"), ready: ready,
                   greeting: ready ? "Ask me anything about this question." : "Explain this question first, then ask me about it.",
                   placeholder: ready ? "Ask anything" : "Explain this question first",
                   outerRadius: outerRadius, inset: inset, open: open) { q in
            guard !store.busy.contains("\(sid)/\(key)/chat") else { return }
            Task { await Tutor.ask(sid, key, q) }
        }
    }
}

/// The floating tutor chat: a round button that opens into a card. The caller owns the lines and the sending.
struct ChatBubble: View {
    let lines: [ChatLine]
    let busy: Bool, ready: Bool
    let greeting: String, placeholder: String
    var outerRadius: CGFloat = L.radius
    var inset: CGFloat = L.inset
    var prompts = QuestionChat.prompts
    @State private var open: Bool
    @State private var draft = ""
    @FocusState private var focused: Bool
    let send: (String) -> Void

    init(lines: [ChatLine], busy: Bool, ready: Bool, greeting: String, placeholder: String, outerRadius: CGFloat = L.radius,
         inset: CGFloat = L.inset, open: Bool = false, send: @escaping (String) -> Void) {
        self.lines = lines; self.busy = busy; self.ready = ready; self.greeting = greeting; self.placeholder = placeholder
        self.outerRadius = outerRadius; self.inset = inset; self.send = send
        _open = State(initialValue: open)
    }

    private var radius: CGFloat { max(8, outerRadius - inset) }          // the closed button: concentric with the column it sits in
    private var buttonSize: CGFloat { max(40, min(52, radius * 2)) }

    var body: some View {
        // Open, it is a card like the others: card radius outside, inner radius on the composer.
        let shape = RoundedRectangle(cornerRadius: open ? L.radius : radius, style: .continuous)
        ZStack(alignment: .topLeading) {
            if open {
                panel.transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.12)))
            } else {
                Button { open = true } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .help("Ask about this question")
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
        .frame(width: open ? 400 : buttonSize, height: open ? 540 : buttonSize, alignment: .topLeading)
        .background {
            ZStack {
                Color.clear.glassEffect(open ? .regular : .regular.tint(Color.accentColor.opacity(0.7)).interactive(), in: shape)
                // Closed: a solid accent under the glass, so the button reads on white pages (Bluebook) too.
                shape.fill(open ? Color(nsColor: .windowBackgroundColor).opacity(0.94) : Color.accentColor.opacity(0.85))
            }
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(open ? 0.25 : 0.2), radius: open ? 20 : 10, y: open ? 8 : 4)
        .animation(.spring(duration: 0.45, bounce: 0.18), value: open)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { open = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.leading, L.inset).padding(.trailing, 12).frame(height: 48)
            if lines.isEmpty && !busy {
                ChatEmpty(greeting: greeting, prompts: prompts, size: 14, enabled: ready) { submit($0) }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            ChatRow(fromStudent: l.fromStudent, text: l.text, size: 14, gutter: 56).transition(.opacity)
                        }
                        if busy && lines.last?.fromStudent != false { ChatTyping() }
                    }
                    .padding(.horizontal, L.inset).padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .chatScrollAnchors()
                .animation(.smooth(duration: 0.3), value: lines.count)
            }
            Composer(placeholder: placeholder, text: $draft, size: 14,
                     enabled: ready, busy: busy, focus: $focused) { submit(draft) }
                .padding([.horizontal, .bottom], L.inset).padding(.top, 10)
        }
        .onAppear { focused = true }
    }

    private func submit(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        draft = ""
        send(q)
    }
}
