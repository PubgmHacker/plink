//  AIStreamClient.swift
//  Plink — M39
//
//  Фикс ℗ 6 из аудита: раньше был `static var baseURL` внутри actor —
//  в Swift 6 это ошибка компиляции (изменяемое глобальное состояние).
//  Стало `static let path`.

import Foundation

actor AIStreamClient {
    static let shared = AIStreamClient()
    static let path = "/api/ai/stream"

    enum StreamEvent {
        case token(String)
        case done
        case failure(String)
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    private var task: URLSessionDataTask?
    private var currentTask: Task<Void, Never>?

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    func stream(messages: [Message], roomID: String?) -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            let work = Task {
                guard let url = URL(string: APIConfig.baseURL + Self.path) else {
                    continuation.yield(.failure("Неверный адрес сервера."))
                    continuation.finish()
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                if let token = AuthTokenStore.shared.token {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                var body: [String: Any] = ["messages": messages.map { ["role": $0.role, "content": $0.content] }]
                if let roomID { body["roomId"] = roomID }
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 120

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(code) else {
                        continuation.yield(.failure(Self.message(forStatus: code)))
                        continuation.finish()
                        return
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        // Сервер шлёт ': ping' каждые 15 с, чтобы прокси не рвал соединение.
                        if line.hasPrefix(":") { continue }
                        guard line.hasPrefix("data:") else { continue }

                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }

                        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let errorCode = object["error"] as? String {
                                let text = object["message"] as? String ?? Self.message(forCode: errorCode)
                                continuation.yield(.failure(text))
                                break
                            }
                            if let choices = object["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String, !content.isEmpty {
                                continuation.yield(.token(content))
                            }
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.failure("Соединение прервалось. Попробуйте ещё раз."))
                    }
                    continuation.finish()
                }
            }

            currentTask = work
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private static func message(forStatus code: Int) -> String {
        switch code {
        case 401: return "Нужно войти заново."
        case 429: return "Слишком много запросов к ИИ. Подождите минуту."
        case 500..<600: return "ИИ временно недоступен."
        default: return "Не удалось получить ответ."
        }
    }

    private static func message(forCode code: String) -> String {
        switch code {
        case "upstream_failed": return "ИИ не ответил. Попробуйте ещё раз."
        case "stream_failed": return "Поток прервался. Попробуйте ещё раз."
        default: return "Ошибка ИИ."
        }
    }
}
