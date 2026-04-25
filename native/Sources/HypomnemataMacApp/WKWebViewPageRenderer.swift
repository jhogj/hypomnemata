import Foundation
import HypomnemataIngestion
import WebKit

public struct WKWebViewPageRenderer: JSPageRenderer {
    public enum RendererError: LocalizedError {
        case invalidURL(String)
        case timeout
        case loadFailed(String)
        case extractionFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .invalidURL(value):
                "URL inválida: \(value)"
            case .timeout:
                "Renderização da página excedeu o tempo limite."
            case let .loadFailed(detail):
                "Falha ao carregar página: \(detail)"
            case let .extractionFailed(detail):
                "Falha ao extrair HTML renderizado: \(detail)"
            }
        }
    }

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 12.0) {
        self.timeout = timeout
    }

    public func renderHTML(url: String) async throws -> String {
        guard let target = URL(string: url) else {
            throw RendererError.invalidURL(url)
        }
        let timeout = self.timeout
        return try await MainActor.run {
            WKWebViewPageRenderer.Session(timeout: timeout, request: URLRequest(url: target))
        }.run()
    }

    @MainActor
    final class Session: NSObject, WKNavigationDelegate {
        private let timeout: TimeInterval
        private let request: URLRequest
        private var continuation: CheckedContinuation<String, Error>?
        private var webView: WKWebView?
        private var timeoutTask: Task<Void, Never>?
        private var retainCycle: Session?

        init(timeout: TimeInterval, request: URLRequest) {
            self.timeout = timeout
            self.request = request
            super.init()
        }

        nonisolated func run() async throws -> String {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                Task { @MainActor in
                    self.start(continuation: continuation)
                }
            }
        }

        private func start(continuation: CheckedContinuation<String, Error>) {
            self.continuation = continuation
            self.retainCycle = self
            let webView = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
                configuration: WKWebViewConfiguration()
            )
            webView.navigationDelegate = self
            self.webView = webView
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.timeout ?? 12.0) * 1_000_000_000)
                await MainActor.run { [weak self] in
                    self?.finish(.failure(RendererError.timeout))
                }
            }
            webView.load(request)
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                self?.captureHTML()
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak self] in
                self?.finish(.failure(RendererError.loadFailed(error.localizedDescription)))
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak self] in
                self?.finish(.failure(RendererError.loadFailed(error.localizedDescription)))
            }
        }

        private func captureHTML() {
            guard let webView else { return }
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
                Task { @MainActor [weak self] in
                    if let error {
                        self?.finish(.failure(RendererError.extractionFailed(error.localizedDescription)))
                        return
                    }
                    if let html = result as? String, !html.isEmpty {
                        self?.finish(.success(html))
                    } else {
                        self?.finish(.failure(RendererError.extractionFailed("HTML vazio")))
                    }
                }
            }
        }

        private func finish(_ result: Result<String, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            webView?.stopLoading()
            webView?.navigationDelegate = nil
            webView = nil
            retainCycle = nil
            switch result {
            case let .success(value):
                continuation.resume(returning: value)
            case let .failure(error):
                continuation.resume(throwing: error)
            }
        }
    }
}
