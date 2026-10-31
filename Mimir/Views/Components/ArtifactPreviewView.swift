import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ArtifactPreviewView: View {
    let language: String
    let code: String

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @State private var showsCode = false
    @State private var showsFullscreen = false
    @State private var showsExporter = false

    static func supports(language: String, code: String) -> Bool {
        let kind = language.lowercased()
        return ["html", "htm", "svg", "javascript", "js", "canvas"].contains(kind)
            || (kind.isEmpty && code.localizedCaseInsensitiveContains("<html"))
    }

    private var html: String {
        let kind = language.lowercased()
        let body: String
        if kind == "svg" {
            body = code
        } else if kind == "js" || kind == "javascript" || kind == "canvas" {
            body = "<canvas id=\"app\" style=\"width:100vw;height:100vh\"></canvas><script>\(code)</script>"
        } else {
            body = code
        }
        let policy = "default-src 'none'; img-src data: blob:; style-src 'unsafe-inline' data:; script-src 'unsafe-inline'; connect-src 'none'; font-src data:;"
        return "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no\"><meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\"><style>html,body{margin:0;min-height:100%;background:#120D1D;color:#F8F6FD;font-family:-apple-system,system-ui,sans-serif}body{overflow:auto}canvas,svg{max-width:100%;height:auto;touch-action:manipulation}</style></head><body>\(body)</body></html>"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(accent.opacity(0.25)).frame(height: 0.7)
            content(height: 300)
        }
        .background(Color(hex: "120D1D"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1))
        .sheet(isPresented: $showsFullscreen) {
            NavigationStack {
                ArtifactWebView(html: html)
                    .background(Color(hex: "120D1D"))
                    .ignoresSafeArea(edges: .bottom)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showsFullscreen = false }
                        }
                    }
                    .navigationTitle("Artifact")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: ArtifactHTMLDocument(text: html),
            contentType: .html,
            defaultFilename: "mimir-artifact.html"
        ) { _ in }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").foregroundStyle(accent)
            Text("Artifact · \(language.isEmpty ? "HTML" : language.uppercased())")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: "F8F6FD"))
            Spacer(minLength: 2)
            Picker("视图", selection: $showsCode) {
                Text("预览").tag(false)
                Text("代码").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 116)
            Button { showsFullscreen = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("全屏预览")
            Button { showsExporter = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("导出 Artifact")
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    @ViewBuilder
    private func content(height: CGFloat) -> some View {
        if showsCode {
            ScrollView([.horizontal, .vertical]) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hex: "EDE5FA"))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: height)
        } else {
            ArtifactWebView(html: html)
                .frame(height: height)
        }
    }
}

private struct ArtifactWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 18 / 255, green: 13 / 255, blue: 29 / 255, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.scrollView.isScrollEnabled = true
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(lastHTML: html) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String
        init(lastHTML: String) { self.lastHTML = lastHTML }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }
}

private struct ArtifactHTMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html] }
    var text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
