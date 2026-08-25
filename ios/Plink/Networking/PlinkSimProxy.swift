//
//  PlinkSimProxy.swift
//  Plink
//
//  Обход неисправного DNS в iOS-симуляторе: когда задана переменная
//  окружения PLINK_PROXY=host:port (её пробрасывает launch-скрипт
//  симулятора), все HTTP(S)-запросы приложения — URLSession.shared,
//  AsyncImage, REST и каталог — уходят через локальный CONNECT-прокси
//  на Маке, где резолвинг имён работает. TLS остаётся сквозным:
//  сертификат проверяется по реальному хосту, прокси видит только
//  туннель. Без переменной окружения (реальное устройство, прод)
//  код бездействует и ничего не регистрирует.
//

import Foundation

enum PlinkSimProxy {
    private(set) static var host: String?
    private(set) static var port: Int = 0

    static var isEnabled: Bool { host != nil }

    /// Читает PLINK_PROXY и включает перехват. Вызывается первой строкой
    /// PlinkApp.init(), до создания сетевых сервисов.
    static func activateIfNeeded() {
        guard host == nil,
              let spec = ProcessInfo.processInfo.environment["PLINK_PROXY"],
              !spec.isEmpty else { return }
        let parts = spec.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let parsedPort = Int(parts[1]),
              (1...65535).contains(parsedPort) else {
            Logger.app.warn("[SimProxy] некорректный PLINK_PROXY: \(spec)")
            return
        }
        host = String(parts[0])
        port = parsedPort
        URLProtocol.registerClass(PlinkSimProxyURLProtocol.self)
        Logger.app.info("[SimProxy] включён, прокси \(spec)")
    }

    /// connectionProxyDictionary для внутренней сессии-форвардера.
    static var proxyDictionary: [AnyHashable: Any] {
        guard let host else { return [:] }
        return [
            "HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
            "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port,
        ]
    }
}

/// Перехватывает каждый http(s)-запрос общей сессии и повторяет его
/// через сессию с CONNECT-прокси. Ответ (или ошибка) ретранслируется
/// исходному клиенту без изменений.
final class PlinkSimProxyURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "plink.simproxy.handled"

    /// Одна сессия-форвардер на процесс: keep-alive, без собственных
    /// URLProtocol (иначе рекурсия), с прокси-словарём.
    private static let forwarder: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = PlinkSimProxy.proxyDictionary
        config.protocolClasses = []
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }()

    private var forwardTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        guard PlinkSimProxy.isEnabled,
              let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return URLProtocol.property(forKey: handledKey, in: request) == nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)
        let task = Self.forwarder.dataTask(with: mutable as URLRequest) { [weak self] data, response, error in
            guard let self, let client = self.client else { return }
            if let error {
                client.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response {
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            }
            if let data, !data.isEmpty {
                client.urlProtocol(self, didLoad: data)
            }
            client.urlProtocolDidFinishLoading(self)
        }
        forwardTask = task
        task.resume()
    }

    override func stopLoading() {
        forwardTask?.cancel()
        forwardTask = nil
    }
}
