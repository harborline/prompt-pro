import AppKit
import SwiftUI
import WebKit

struct BlockNoteEditorView: NSViewRepresentable {
    @Binding var markdown: String
    let colorScheme: ColorScheme
    let aiConfig: LocalAIConfig

    func makeCoordinator() -> Coordinator {
        Coordinator(markdown: $markdown)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let editorRootURL = Self.editorRootURL {
            let schemeHandler = BlockNoteEditorSchemeHandler(rootURL: editorRootURL)
            configuration.setURLSchemeHandler(schemeHandler, forURLScheme: Self.editorScheme)
            context.coordinator.schemeHandler = schemeHandler
        }
        configuration.userContentController.add(context.coordinator, name: "blockNoteBridge")
        let configScript = Self.makeInitialConfigScript(for: aiConfig)
        configuration.userContentController.addUserScript(
            WKUserScript(source: configScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if Self.editorRootURL != nil,
           let url = URL(string: "\(Self.editorScheme)://bundle/index.html") {
            webView.load(URLRequest(url: url))
        } else {
            webView.loadHTMLString(
                """
                <html>
                  <body style="background: #2e3440; color: white; font: 14px -apple-system, BlinkMacSystemFont, sans-serif;">
                    BlockNote editor assets are missing. Run npm run build:blocknote.
                  </body>
                </html>
                """,
                baseURL: nil
            )
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.apply(markdown: markdown, colorScheme: colorScheme, aiConfig: aiConfig)
    }

    private static let editorScheme = "prompt-producer-editor"

    private static var editorRootURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("BlockNoteEditor/index.html"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BlockNoteEditor/index.html"),
            Bundle.main.bundleURL.appendingPathComponent("PromptProducer_PromptProducer.bundle/BlockNoteEditor/index.html"),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("PromptProducer_PromptProducer.bundle/BlockNoteEditor/index.html"),
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("PromptProducer_PromptProducer.bundle/BlockNoteEditor/index.html")
        ]

        return candidates
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }?
            .deletingLastPathComponent()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private var markdown: Binding<String>
        weak var webView: WKWebView?
        var schemeHandler: BlockNoteEditorSchemeHandler?
        private var isReady = false
        private var lastAppliedMarkdown: String?
        private var pendingMarkdown: String?
        private var pendingTheme: ColorScheme?
        private var pendingAIConfig: LocalAIConfig?
        private var lastAppliedAIConfig: LocalAIConfig?

        init(markdown: Binding<String>) {
            self.markdown = markdown
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            webView.evaluateJavaScript("document.getElementById('root')?.childElementCount ?? -1") { result, error in
                if let error {
                    AppLog.lifecycle.error("BlockNote editor load probe failed: \(error.localizedDescription, privacy: .public)")
                    return
                }

                if let childCount = result as? Int {
                    AppLog.lifecycle.info("BlockNote editor root child count: \(childCount, privacy: .public)")
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "blockNoteBridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            switch type {
            case "ready":
                isReady = true
                applyPendingValues()
            case "change":
                guard let nextMarkdown = body["markdown"] as? String else {
                    return
                }

                lastAppliedMarkdown = nextMarkdown
                if markdown.wrappedValue != nextMarkdown {
                    markdown.wrappedValue = nextMarkdown
                }
            case "aiRequest":
                guard let requestID = body["requestID"] as? String,
                      let prompt = body["prompt"] as? String else {
                    return
                }

                let context = body["context"] as? String ?? markdown.wrappedValue
                AppLog.ai.info(
                    "AI bridge request id=\(requestID, privacy: .public) promptLen=\(prompt.count, privacy: .public) contextLen=\(context.count, privacy: .public)"
                )
                Task { [weak self] in
                    do {
                        let text = try await LocalFoundationModelAI.respond(to: prompt, context: context)
                        AppLog.ai.info(
                            "AI bridge response id=\(requestID, privacy: .public) outputLen=\(text.count, privacy: .public)"
                        )
                        await MainActor.run {
                            self?.completeAIRequest(requestID: requestID, text: text, error: nil)
                        }
                    } catch {
                        AppLog.ai.error("Local AI request failed id=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                        await MainActor.run {
                            self?.completeAIRequest(requestID: requestID, text: nil, error: error.localizedDescription)
                        }
                    }
                }
            case "aiDebug":
                let phase = body["phase"] as? String ?? "unknown"
                let detail = body["detail"] as? String ?? ""
                AppLog.ai.info("BlockNote AI debug phase=\(phase, privacy: .public) detail=\(detail, privacy: .public)")
            case "error":
                if let errorMessage = body["message"] as? String {
                    AppLog.lifecycle.error("BlockNote bridge error: \(errorMessage, privacy: .public)")
                    SentryObservability.captureMessage(errorMessage, context: "blocknote_bridge")
                }
            default:
                break
            }
        }

        func apply(markdown: String, colorScheme: ColorScheme, aiConfig: LocalAIConfig) {
            pendingMarkdown = markdown
            pendingTheme = colorScheme
            pendingAIConfig = aiConfig
            applyPendingValues()
        }

        private func applyPendingValues() {
            guard isReady, let webView else {
                return
            }

            if let pendingTheme {
                let theme = pendingTheme == .dark ? "dark" : "light"
                webView.evaluateJavaScript("window.promptProducer?.setTheme(\(Self.javascriptString(theme)));")
                self.pendingTheme = nil
            }

            if let pendingAIConfig {
                if pendingAIConfig != lastAppliedAIConfig {
                    lastAppliedAIConfig = pendingAIConfig
                    webView.evaluateJavaScript("window.promptProducer?.setAIConfig(\(Self.javascriptValue(for: pendingAIConfig)));")
                }
                self.pendingAIConfig = nil
            }

            guard let pendingMarkdown else {
                return
            }

            if pendingMarkdown != lastAppliedMarkdown {
                lastAppliedMarkdown = pendingMarkdown
                let escaped = Self.javascriptString(pendingMarkdown)
                webView.evaluateJavaScript("window.promptProducer?.setMarkdown(\(escaped)); window.promptProducer?.focus();")
            }

            self.pendingMarkdown = nil
        }

        @MainActor
        private func completeAIRequest(requestID: String, text: String?, error: String?) {
            let payload = NativeAIResponse(requestID: requestID, text: text, error: error)
            webView?.evaluateJavaScript("window.promptProducerResolveAI?.(\(Self.javascriptValue(for: payload)));")
        }

        private static func javascriptValue(for config: LocalAIConfig) -> String {
            let payload = JavaScriptAIConfig(
                model: config.model.trimmingCharacters(in: .whitespacesAndNewlines),
                nativeAIAvailable: true,
                nativeAIProviderName: "Apple Foundation Models"
            )

            guard let data = try? JSONEncoder().encode(payload),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "{}"
            }

            return encoded
        }

        private static func javascriptValue<T: Encodable>(for payload: T) -> String {
            guard let data = try? JSONEncoder().encode(payload),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "{}"
            }

            return encoded
        }

        private static func javascriptString(_ string: String) -> String {
            guard let data = try? JSONEncoder().encode(string),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "\"\""
            }

            return encoded
        }
    }
}

private extension BlockNoteEditorView {
    static func makeInitialConfigScript(for config: LocalAIConfig) -> String {
        let payload = JavaScriptAIConfig(
            model: config.model.trimmingCharacters(in: .whitespacesAndNewlines),
            nativeAIAvailable: true,
            nativeAIProviderName: "Apple Foundation Models"
        )

        guard let data = try? JSONEncoder().encode(payload),
              let encoded = String(data: data, encoding: .utf8) else {
            return "window.__INITIAL_AI_CONFIG = {};"
        }

        return "window.__INITIAL_AI_CONFIG = \(encoded);"
    }
}

final class BlockNoteEditorSchemeHandler: NSObject, WKURLSchemeHandler {
    private let rootURL: URL
    private let standardizedRootPath: String

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        standardizedRootPath = self.rootURL.path
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(BlockNoteEditorSchemeError.invalidURL)
            return
        }

        let requestedPath = requestURL.path.isEmpty || requestURL.path == "/"
            ? "index.html"
            : String(requestURL.path.dropFirst())
        let fileURL = rootURL.appendingPathComponent(requestedPath).standardizedFileURL

        guard fileURL.path == rootURL.appendingPathComponent("index.html").standardizedFileURL.path ||
              fileURL.path.hasPrefix(standardizedRootPath + "/") else {
            urlSchemeTask.didFailWithError(BlockNoteEditorSchemeError.pathOutsideBundle)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let response = URLResponse(
                url: requestURL,
                mimeType: Self.mimeType(for: fileURL),
                expectedContentLength: data.count,
                textEncodingName: Self.textEncodingName(for: fileURL)
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "html":
            "text/html"
        case "js":
            "text/javascript"
        case "css":
            "text/css"
        case "woff":
            "font/woff"
        case "woff2":
            "font/woff2"
        default:
            "application/octet-stream"
        }
    }

    private static func textEncodingName(for fileURL: URL) -> String? {
        switch fileURL.pathExtension.lowercased() {
        case "html", "js", "css":
            "utf-8"
        default:
            nil
        }
    }
}

enum BlockNoteEditorSchemeError: Error {
    case invalidURL
    case pathOutsideBundle
}

private struct JavaScriptAIConfig: Encodable {
    var model: String
    var nativeAIAvailable: Bool
    var nativeAIProviderName: String
}

private struct NativeAIResponse: Encodable {
    var requestID: String
    var text: String?
    var error: String?
}
