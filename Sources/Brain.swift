import Foundation
import FoundationModels

/// Who does the explaining. Apple's on-device model is free, private and needs no setup, so it is the default;
/// Claude, ChatGPT or Gemini (with the student's own key) explain in more depth and can read the screenshot.
/// None of them ever decides right or wrong: that comes from official answers or the student's mark.
enum Brain {
    static var provider: Provider {
        if let p = UserDefaults.standard.string(forKey: "brain").flatMap(Provider.init(rawValue:)), p == .apple || p.hasKey { return p }
        return Claude.hasKey ? .claude : .apple
    }
    static var appleReady: Bool { SystemLanguageModel.default.isAvailable }
    static var ready: Bool { provider != .apple || appleReady }
    static var name: String { provider.name }
    static var seesImages: Bool { provider.seesImages }

    /// The provider for one task: the student's pin from Settings ("brain.<task>"), or the main choice when that is "auto" or can't run.
    static func provider(for task: AITask?) -> Provider { resolve(task.flatMap { UserDefaults.standard.string(forKey: "brain.\($0.rawValue)") }) }
    static func resolve(_ pin: String?) -> Provider {
        guard let p = pin.flatMap(Provider.init(rawValue:)), p == .apple ? appleReady : p.hasKey else { return provider }
        return p
    }

    /// One request to whichever provider is chosen. Messages are Anthropic-shaped (text and local image parts);
    /// Apple's model gets the text only, so callers include the screen's text when images can't be seen.
    static func send(task: AITask? = nil, system: String, messages: [[String: Any]], schema: [String: Any]? = nil, base: URL, effort: String = "high") async throws -> String {
        switch provider(for: task) {
        case .claude: return try await Claude.send(system: system, messages: messages, schema: schema, base: base, effort: effort).text
        case .openai: return try await OpenAI.send(system: system, messages: messages, schema: schema, base: base)
        case .gemini: return try await Gemini.send(system: system, messages: messages, schema: schema, base: base)
        case .apple:
            let text = messages.map { m -> String in
                let role = (m["role"] as? String) == "assistant" ? "Tutor" : "Student"
                let parts = (m["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? [(m["content"] as? String) ?? ""]
                return "\(role): " + parts.joined(separator: "\n")
            }.joined(separator: "\n\n")
            // The on-device context is small (4K tokens): keep the newest part of a long conversation.
            return try await Apple.send(system: system, prompt: String(text.suffix(9000)), schema: schema)
        }
    }

    /// Why the on-device model can't run, in plain words (nil when it can).
    static var appleProblem: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in System Settings."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading. Try again in a few minutes."
        case .unavailable(.deviceNotEligible): "This Mac can't run Apple Intelligence. Add a key for another tutor."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }
}

/// The jobs the student can give to a different provider in Settings.
enum AITask: String, CaseIterable {
    case explain, debrief, chat, tutor, extract, practice
    var name: String {
        switch self { case .explain: "Explanations"; case .debrief: "Test reviews"; case .chat: "Question chat"; case .tutor: "Tutor chat"; case .extract: "Reading score pages"; case .practice: "Practice questions" }
    }
    var icon: String {
        switch self { case .explain: "lightbulb.fill"; case .debrief: "chart.bar.fill"; case .chat: "bubble.left.fill"; case .tutor: "bubble.left.and.bubble.right.fill"; case .extract: "doc.text.viewfinder"; case .practice: "pencil.and.list.clipboard" }
    }
}

/// Apple's on-device model with the same JSON-schema contract as `Claude.send`, so the tutor doesn't care which runs.
enum Apple {
    /// One answer. With a schema, the reply is JSON that matches it (guided generation, so it always parses).
    static func send(system: String, prompt: String, schema: [String: Any]? = nil) async throws -> String {
        let session = LanguageModelSession(instructions: system)
        if let schema {
            let g = try GenerationSchema(root: dynamic(schema, name: "Reply"), dependencies: [])
            return try await session.respond(to: prompt, schema: g).content.jsonString
        }
        return try await session.respond(to: prompt).content
    }

    /// Converts the subset of JSON Schema the tutor uses (object, string, enum, array of objects) to Apple's form.
    static func dynamic(_ s: [String: Any], name: String) -> DynamicGenerationSchema {
        if let values = s["enum"] as? [String] { return DynamicGenerationSchema(name: name, anyOf: values) }
        switch s["type"] as? String {
        case "object":
            let props = s["properties"] as? [String: [String: Any]] ?? [:]
            return DynamicGenerationSchema(name: name, properties: props.keys.sorted().map { k in
                .init(name: k, description: props[k]?["description"] as? String, schema: dynamic(props[k]!, name: name + "_" + k))
            })
        case "array":
            return DynamicGenerationSchema(arrayOf: dynamic(s["items"] as? [String: Any] ?? ["type": "string"], name: name + "_item"))
        default:
            return DynamicGenerationSchema(type: String.self)
        }
    }
}
