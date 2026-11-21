import Foundation
import Security

/// Explanation providers. Claude keeps its own client in Tutor.swift; OpenAI and Gemini are raw HTTPS here.
/// Model ids: developers.openai.com/api/docs/models and aistudio.google.com/docs/models (ai.google.dev redirects there).
enum Provider: String, CaseIterable {
    case apple, claude, openai, gemini

    var name: String {
        switch self { case .apple: "Apple Intelligence"; case .claude: "Claude"; case .openai: "ChatGPT"; case .gemini: "Gemini" }
    }
    var keyURL: URL? {
        switch self {
        case .apple: nil
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        }
    }
    var seesImages: Bool { self != .apple }
    var defaultModel: String {
        switch self { case .apple: "on-device"; case .claude: Claude.model; case .openai: "gpt-6-astra"; case .gemini: "gemini-3.8-flash" }
    }
    var model: String {
        let o = UserDefaults.standard.string(forKey: "\(rawValue)Model")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return o?.isEmpty == false ? o! : defaultModel
    }

    private var account: String? { self == .openai ? "openai-api-key" : self == .gemini ? "gemini-api-key" : nil }
    var key: String? {
        switch self {
        case .apple: nil
        case .claude: Claude.apiKey
        default: Self.keychain(account!)
        }
    }
    var hasKey: Bool { self == .apple || !(key ?? "").isEmpty }
    func setKey(_ k: String?) {
        switch self {
        case .apple: break
        case .claude: Claude.setKey(k)
        default: Self.setKeychain(k?.trimmingCharacters(in: .whitespacesAndNewlines), account!)
        }
    }

    // Keychain (Tutor.swift) has one fixed account, so these two mirror it per account.
    private static func keychain(_ account: String) -> String? {
        if Keychain.testing { return nil }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Keychain.service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    private static func setKeychain(_ value: String?, _ account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Keychain.service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard let value, !value.isEmpty else { return }
        SecItemAdd(q.merging([kSecValueData as String: Data(value.utf8)]) { $1 } as CFDictionary, nil)
    }

    enum Failure: LocalizedError {
        case noKey(Provider), http(Provider, Int, String), empty(Provider)
        var errorDescription: String? {
            switch self {
            case .noKey(let p): "Add a \(p.name) API key in Settings."
            case .http(let p, let code, let msg): "\(p.name) error \(code): \(msg)"
            case .empty(let p): "\(p.name) sent back nothing."
            }
        }
    }

    /// POSTs JSON and returns the parsed object; non-200 becomes Failure.http with the API's own message.
    fileprivate func post(_ url: String, headers: [String: String], body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure.http(self, status, ((json["error"] as? [String: Any])?["message"] as? String) ?? String(decoding: data, as: UTF8.self))
        }
        return json
    }

    /// Anthropic-format messages → (role, parts); parts are ("text", string) or ("image", base64 jpeg).
    /// Other block types (thinking etc. in saved Claude replies) are dropped.
    fileprivate static func flatten(_ messages: [[String: Any]], base: URL) throws -> [(role: String, parts: [(kind: String, value: String)])] {
        try messages.map { m in
            let role = m["role"] as? String ?? "user"
            if let s = m["content"] as? String { return (role, [("text", s)]) }
            let parts = try (m["content"] as? [[String: Any]] ?? []).compactMap { p -> (kind: String, value: String)? in
                if let path = p["local_path"] as? String { return ("image", try Data(contentsOf: base.appendingPathComponent(path)).base64EncodedString()) }
                if p["type"] as? String == "text", let t = p["text"] as? String { return ("text", t) }
                return nil
            }
            return (role, parts)
        }
    }
}

enum OpenAI {
    static func body(system: String, messages: [[String: Any]], schema: [String: Any]?, base: URL) throws -> [String: Any] {
        var input: [[String: Any]] = [["role": "system", "content": system]]
        for m in try Provider.flatten(messages, base: base) {
            if m.role == "assistant" { input.append(["role": "assistant", "content": m.parts.map(\.value).joined()]); continue }
            input.append(["role": "user", "content": m.parts.map { p -> [String: Any] in
                p.kind == "image" ? ["type": "input_image", "image_url": "data:image/jpeg;base64,\(p.value)"] : ["type": "input_text", "text": p.value]
            }])
        }
        var b: [String: Any] = ["model": Provider.openai.model, "input": input]
        if let schema { b["text"] = ["format": ["type": "json_schema", "name": "reply", "schema": schema, "strict": true]] }
        return b
    }

    static func send(system: String, messages: [[String: Any]], schema: [String: Any]? = nil, base: URL) async throws -> String {
        guard let key = Provider.openai.key, !key.isEmpty else { throw Provider.Failure.noKey(.openai) }
        let json = try await Provider.openai.post("https://api.openai.com/v1/responses", headers: ["authorization": "Bearer \(key)"],
                                                  body: body(system: system, messages: messages, schema: schema, base: base))
        let parts = (json["output"] as? [[String: Any]] ?? []).flatMap { $0["content"] as? [[String: Any]] ?? [] }
        let text = parts.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw Provider.Failure.empty(.openai) }
        return text
    }
}

enum Gemini {
    static func body(system: String, messages: [[String: Any]], schema: [String: Any]?, base: URL) throws -> [String: Any] {
        let contents = try Provider.flatten(messages, base: base).map { m -> [String: Any] in
            ["role": m.role == "assistant" ? "model" : "user", "parts": m.parts.map { p -> [String: Any] in
                p.kind == "image" ? ["inlineData": ["mimeType": "image/jpeg", "data": p.value]] : ["text": p.value]
            }]
        }
        var b: [String: Any] = ["systemInstruction": ["parts": [["text": system]]], "contents": contents]
        // responseJsonSchema takes plain JSON Schema (additionalProperties is supported), so no stripping.
        if let schema { b["generationConfig"] = ["responseMimeType": "application/json", "responseJsonSchema": schema] }
        return b
    }

    static func send(system: String, messages: [[String: Any]], schema: [String: Any]? = nil, base: URL) async throws -> String {
        guard let key = Provider.gemini.key, !key.isEmpty else { throw Provider.Failure.noKey(.gemini) }
        let json = try await Provider.gemini.post("https://generativelanguage.googleapis.com/v1beta/models/\(Provider.gemini.model):generateContent",
                                                  headers: ["x-goog-api-key": key], body: body(system: system, messages: messages, schema: schema, base: base))
        let parts = ((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw Provider.Failure.empty(.gemini) }
        return text
    }
}

extension Provider {
    /// Builds (without sending) one request body per provider and returns the problems found.
    static func selfCheck() -> [String] {
        var bad: [String] = []
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("provider-check-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try? Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: base.appendingPathComponent("x.jpg"))
        let msgs: [[String: Any]] = [["role": "user", "content": [["type": "image", "local_path": "x.jpg"], ["type": "text", "text": "hi"]]],
                                     ["role": "assistant", "content": [["type": "text", "text": "ok"]]]]
        let schema: [String: Any] = ["type": "object", "properties": ["a": ["type": "string"]], "required": ["a"], "additionalProperties": false]
        for (p, make) in [(Provider.openai, OpenAI.body), (.gemini, Gemini.body)] {
            guard let b = try? make("sys", msgs, schema, base), JSONSerialization.isValidJSONObject(b),
                  let s = (try? JSONSerialization.data(withJSONObject: b, options: .withoutEscapingSlashes)).map({ String(decoding: $0, as: UTF8.self) }) else { bad.append("\(p.name): body invalid"); continue }
            if p == .openai {
                if !s.contains("\"model\":\"\(p.model)\"") { bad.append("openai: model missing") }
                if !s.contains("input_image") || !s.contains("data:image/jpeg;base64,") { bad.append("openai: image missing") }
                if !s.contains("json_schema") || !s.contains("\"strict\":true") { bad.append("openai: schema missing") }
            } else {
                if p.model.isEmpty { bad.append("gemini: model missing") }
                if !s.contains("inlineData") || !s.contains("image/jpeg") { bad.append("gemini: image missing") }
                if !s.contains("responseJsonSchema") || !s.contains("application/json") { bad.append("gemini: schema missing") }
                if !s.contains("\"role\":\"model\"") { bad.append("gemini: assistant role not mapped") }
            }
        }
        return bad
    }
}
