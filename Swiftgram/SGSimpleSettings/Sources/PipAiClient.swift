import Foundation

public func pipAiComplete(
    system: String,
    prompt: String,
    maxTokens: Int = 300,
    completion: @escaping (String?) -> Void
) {
    let extra = AyuGramSettings.shared.extra
    let customKey = extra.pipAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

    func extractText(from data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let choices = obj["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let content = obj["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let str = String(data: data, encoding: .utf8), !str.isEmpty {
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    if !customKey.isEmpty {
        let provider = extra.pipAiProvider
        var endpoint = "https://api.openai.com/v1/chat/completions"
        var model = "gpt-4o-mini"
        if provider == 2 {
            endpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            model = "gemini-2.0-flash"
        } else if provider == 3 {
            endpoint = "https://api.groq.com/openai/v1/chat/completions"
            model = "llama-3.3-70b-versatile"
        }
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + customKey, forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": 0.3
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let reply = data.flatMap { extractText(from: $0) }
            DispatchQueue.main.async {
                completion(reply)
            }
        }.resume()
    } else {
        // Free public AI endpoint
        guard let url = URL(string: "https://text.pollinations.ai/openai") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt]
            ],
            "model": "openai"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let reply = data.flatMap { extractText(from: $0) }
            DispatchQueue.main.async {
                completion(reply)
            }
        }.resume()
    }
}
