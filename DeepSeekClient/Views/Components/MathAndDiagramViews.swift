import SwiftUI
import WebKit

/// 公式渲染（KaTeX）。
///
/// 采用内嵌 WebView 加载渲染脚本，首次渲染需要联网；
/// 离线时展示公式源码，不会影响对话可用性。
struct LatexBlockView: View {

    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WebContentBlock(
                html: Self.html(for: source),
                height: 90,
                identifier: "latex"
            )
            Text("公式 · 离线时以上内容可能显示为源码")
                .font(AppFont.chipCompact)
                .foregroundStyle(AppColor.tertiaryText)
        }
    }

    static func html(for latex: String) -> String {
        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
        <style>
          body { margin:0; padding:6px 2px; background:transparent; font-size:17px;
                 color: var(--text, #111); word-break: break-word; }
          .fallback { font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
                      font-size:13px; white-space:pre-wrap; }
        </style></head>
        <body>
        <div id="root" class="fallback">`\(escaped)`</div>
        <script>
          function render() {
            var root = document.getElementById('root');
            if (window.katex) {
              try {
                root.className = '';
                katex.render(`\(escaped)`, root, { throwOnError:false, displayMode:true });
              } catch (e) { /* keep fallback */ }
              window.webkit.messageHandlers.sizeChanged.postMessage(root.scrollHeight);
            }
          }
          window.addEventListener('load', render);
          setTimeout(render, 800);
        </script>
        </body></html>
        """
    }
}

/// Mermaid 图表渲染。
struct MermaidBlockView: View {

    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WebContentBlock(
                html: Self.html(for: source),
                height: 240,
                identifier: "mermaid"
            )
            Text("图表 · 由 Mermaid 渲染")
                .font(AppFont.chipCompact)
                .foregroundStyle(AppColor.tertiaryText)
        }
    }

    static func html(for diagram: String) -> String {
        let escaped = diagram
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
        <style>
          body { margin:0; padding:6px; background:transparent; }
          pre.fallback { font-family: ui-monospace, Menlo, monospace; font-size:12px;
                         white-space:pre-wrap; color:#666; }
          .mermaid { text-align:center; }
        </style></head>
        <body>
        <pre class="fallback" id="fallback">\(escaped)</pre>
        <div class="mermaid" id="diagram" style="display:none">\(escaped)</div>
        <script>
          function render() {
            if (!window.mermaid) { return; }
            try {
              mermaid.initialize({ startOnLoad:false, theme:'neutral' });
              var el = document.getElementById('diagram');
              var out = mermaid.render('graphDiv', `\(escaped)`);
              out.then(function(result){
                document.getElementById('fallback').style.display = 'none';
                el.style.display = 'block';
                el.innerHTML = result.svg;
                window.webkit.messageHandlers.sizeChanged.postMessage(document.body.scrollHeight);
              }).catch(function(e){});
            } catch (e) {}
          }
          window.addEventListener('load', render);
          setTimeout(render, 900);
        </script>
        </body></html>
        """
    }
}

/// 通用内嵌网页块：透明背景、自动高度、禁止滚动回弹。
struct WebContentBlock: UIViewRepresentable {

    let html: String
    var height: CGFloat
    var identifier: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "sizeChanged")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastIdentifier != identifier {
            context.coordinator.lastIdentifier = identifier
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var lastIdentifier: String?
        private var reportedHeight: CGFloat = 0
        var onHeightChange: ((CGFloat) -> Void)?

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let value = message.body as? CGFloat, value > 0 else { return }
            guard abs(value - reportedHeight) > 4 else { return }
            reportedHeight = value
            onHeightChange?(value)
        }
    }
}
