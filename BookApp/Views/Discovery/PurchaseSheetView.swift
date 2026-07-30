import SwiftUI
#if canImport(SafariServices)
import SafariServices
#endif

struct PurchaseSheetView: View {
    let book: Book
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: Theme.paddingLarge) {
                // Book info header
                HStack(spacing: Theme.paddingMedium) {
                    AsyncImage(url: URL(string: book.largeCoverURL ?? book.thumbnailURL ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 90)
                                .cornerRadius(Theme.cornerRadiusSmall)
                        default:
                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                .fill(Theme.parchment)
                                .frame(width: 60, height: 90)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title)
                            .font(Theme.serifBold(18))
                            .foregroundColor(Theme.primaryText)
                            .lineLimit(2)

                        Text(book.authorDisplay)
                            .font(Theme.body(14))
                            .foregroundColor(Theme.secondaryText)
                    }

                    Spacer()
                }
                .padding(.horizontal)

                Divider()

                // Purchase options
                VStack(spacing: 12) {
                    Text("Where would you like to buy?")
                        .font(Theme.body(15))
                        .foregroundColor(Theme.secondaryText)

                    if let url = book.amazonURL {
                        purchaseButton(
                            title: "Amazon",
                            icon: "cart.fill",
                            color: Color(red: 1.0, green: 0.6, blue: 0.0),
                            url: url
                        )
                    }

                    if let url = book.appleBooksURL {
                        purchaseButton(
                            title: "Apple Books",
                            icon: "book.fill",
                            color: .blue,
                            url: url
                        )
                    }

                    if let url = book.bookshopURL {
                        purchaseButton(
                            title: "Bookshop.org",
                            icon: "building.columns.fill",
                            color: Theme.positive,
                            url: url
                        )
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, Theme.paddingMedium)
            .background(Theme.background)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { onDismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func purchaseButton(title: String, icon: String, color: Color, url: URL) -> some View {
        Button {
            #if os(iOS)
            PurchaseSheetView.openInAppBrowser(url)
            #else
            // On macOS, open in default browser
            // NSWorkspace.shared.open(url) would be used in real macOS build
            #endif
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
                    .frame(width: 30)

                Text(title)
                    .font(Theme.body(16).bold())
                    .foregroundColor(Theme.primaryText)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.muted)
            }
            .padding()
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cornerRadiusMedium)
        }
    }
}

// MARK: - In-app browser (iOS only)

#if os(iOS)
extension PurchaseSheetView {
    /// Presents an in-app Safari browser via UIKit, on top of whatever is currently
    /// showing. Because it's presented on the UIKit controller stack (not as a nested
    /// SwiftUI `.sheet`), closing the browser returns to the purchase sheet instead of
    /// dismissing it.
    static func openInAppBrowser(_ url: URL) {
        guard let top = topViewController() else { return }
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let safariVC = SFSafariViewController(url: url, configuration: config)
        safariVC.preferredControlTintColor = UIColor(Theme.accent)
        top.present(safariVC, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif
