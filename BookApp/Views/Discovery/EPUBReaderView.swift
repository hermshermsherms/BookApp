import SwiftUI
import WebKit

struct EPUBReaderView: View {
    let book: Book
    let resource: BookReadingResource

    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.07, blue: 0.06).ignoresSafeArea()

            EPUBWebReader(
                url: resource.readerURL,
                isLoading: $isLoading,
                loadError: $loadError
            )

            if isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(.white)
                    Text("Opening the preview…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            if let loadError {
                VStack(spacing: 14) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                    Text("Reader unavailable")
                        .font(.headline)
                    Text(loadError)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .padding(24)
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.88), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct EPUBWebReader: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard view.url != url, !view.isLoading else { return }
        view.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: EPUBWebReader

        init(parent: EPUBWebReader) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            parent.isLoading = true
            parent.loadError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            parent.isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error
        ) {
            parent.isLoading = false
            parent.loadError = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            parent.isLoading = false
            parent.loadError = error.localizedDescription
        }
    }
}
