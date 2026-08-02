import SceneKit
import SwiftUI
import UIKit

struct BookCardView: View {
    let book: Book
    let catalog: [Book]
    let isCurrent: Bool
    let onSave: () -> Void
    let onBuy: () -> Void
    let onSkip: () -> Void
    let onBrowseSimilar: (Book, [Book]) -> Void
    let onReadEPUB: (BookReadingResource) -> Void

    @State private var isSynopsisExpanded = false
    @State private var similarBooks: [Book] = []
    @State private var isLoadingSimilar = false
    @State private var isFindingEPUB = false
    @State private var epubError: String?
    @State private var synopsisFrame: CGRect = .zero

    var body: some View {
        GeometryReader { geometry in
            let pageWidth = UIScreen.main.bounds.width

            VStack(spacing: 0) {
                Spacer(minLength: max(8, geometry.safeAreaInsets.top))

                InteractiveBookCover(
                    imageURL: book.highQualityImageURL,
                    title: book.title,
                    author: book.authorDisplay,
                    pageCount: book.pageCount
                )
                .frame(
                    width: min(pageWidth - 18, 360),
                    height: isSynopsisExpanded
                        ? min(geometry.size.height * 0.24, 205)
                        : min(geometry.size.height * 0.48, 390)
                )
                .animation(.easeInOut(duration: 0.28), value: isSynopsisExpanded)
                .accessibilityLabel("Interactive cover for \(book.title)")
                .accessibilityHint("Drag to rotate the book")

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(book.title)
                                .font(Theme.serifBold(24))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)

                            Text(book.authorDisplay)
                                .font(Theme.body(16))
                                .foregroundStyle(.white.opacity(0.82))

                            BookMetadataStrip(book: book)

                            SynopsisText(
                                description: book.description,
                                isExpanded: $isSynopsisExpanded
                            )
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: SynopsisFramePreferenceKey.self,
                                        value: proxy.frame(in: .named("book-card"))
                                    )
                                }
                            }
                            .transition(.opacity)
                        }
                        .frame(width: max(0, pageWidth - 104), alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        BookActionRail(
                            onSave: onSave,
                            onBuy: onBuy,
                            onReadEPUB: findEPUB,
                            onSkip: onSkip,
                            isFindingEPUB: isFindingEPUB
                        )
                    }

                    SimilarBooksBanner(
                        title: "Similar to \(book.title)",
                        isLoading: isLoadingSimilar,
                        isEnabled: !similarBooks.isEmpty,
                        action: openSimilarFeed
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(
                    width: max(0, pageWidth - 40),
                    alignment: .leading
                )
                .padding(.horizontal, 20)

                Spacer(minLength: max(98, geometry.safeAreaInsets.bottom + 76))
            }
            .frame(width: pageWidth, height: geometry.size.height)
            .background(Color.clear)
            .coordinateSpace(name: "book-card")
            .onPreferenceChange(SynopsisFramePreferenceKey.self) { synopsisFrame = $0 }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { tap in
                    guard isSynopsisExpanded, !synopsisFrame.contains(tap.location) else { return }
                    withAnimation(.easeInOut(duration: 0.24)) {
                        isSynopsisExpanded = false
                    }
                }
            )
        }
        .task(id: isCurrent) {
            guard isCurrent, similarBooks.isEmpty else { return }
            await loadSimilarBooks()
        }
        .alert("Preview unavailable", isPresented: Binding(
            get: { epubError != nil },
            set: { if !$0 { epubError = nil } }
        )) {
            Button("OK", role: .cancel) { epubError = nil }
        } message: {
            Text(epubError ?? "A readable edition could not be found.")
        }
    }

    private func findEPUB() {
        guard !isFindingEPUB else { return }
        isFindingEPUB = true
        Task {
            defer { isFindingEPUB = false }
            do {
                let resource = try await GoogleBooksService.shared.fetchReadingResource(for: book)
                onReadEPUB(resource)
            } catch {
                epubError = error.localizedDescription
            }
        }
    }

    private func openSimilarFeed() {
        guard let selected = similarBooks.first else { return }
        onBrowseSimilar(selected, browseCatalog(startingWith: selected))
    }

    private func loadSimilarBooks() async {
        let local = rankedLocalRecommendations()
        similarBooks = local

        guard Config.GoogleBooks.apiKey != nil else { return }
        isLoadingSimilar = local.isEmpty
        defer { isLoadingSimilar = false }

        guard let live = try? await GoogleBooksService.shared.fetchSimilarBooks(to: book, maxResults: 12) else {
            return
        }

        var seen = Set<String>([book.id])
        let merged = (live + local).filter { seen.insert($0.id).inserted }
        similarBooks = Array(merged.prefix(12))
    }

    private func rankedLocalRecommendations() -> [Book] {
        let bookAuthors = Set(book.authors.map { $0.lowercased() })
        let bookCategories = Set(book.categories.map { $0.lowercased() })

        return catalog
            .filter {
                $0.id != book.id
                    && $0.title.compare(book.title, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
            }
            .map { candidate -> (Book, Int) in
                let authors = Set(candidate.authors.map { $0.lowercased() })
                let categories = Set(candidate.categories.map { $0.lowercased() })
                let score = bookAuthors.intersection(authors).count * 5
                    + bookCategories.intersection(categories).count * 3
                    + (candidate.averageRating == nil ? 0 : 1)
                return (candidate, score)
            }
            .sorted {
                if $0.1 == $1.1 {
                    return ($0.0.averageRating ?? 0) > ($1.0.averageRating ?? 0)
                }
                return $0.1 > $1.1
            }
            .prefix(10)
            .map(\.0)
    }

    private func browseCatalog(startingWith selected: Book) -> [Book] {
        var seen = Set<String>()
        return ([selected] + similarBooks + catalog).filter { seen.insert($0.id).inserted }
    }
}

private struct BookMetadataStrip: View {
    let book: Book

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 13) {
                if book.averageRating != nil {
                    metadata(icon: "star.fill", text: book.ratingDisplay, color: .white)
                }
                if book.pageCount != nil {
                    metadata(icon: "book.pages", text: book.pageCountDisplay, color: .white.opacity(0.78))
                }
                if let date = book.publishedDate {
                    metadata(icon: "calendar", text: date, color: .white.opacity(0.78))
                }
                ForEach(book.categories, id: \.self) { category in
                    metadata(icon: "tag.fill", text: category, color: .white.opacity(0.9))
                }
            }
        }
    }

    private func metadata(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
    }
}

private struct SynopsisText: View {
    let description: String?
    @Binding var isExpanded: Bool

    var body: some View {
        if let description, !description.isEmpty {
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(description)
                            .font(Theme.body(14))
                            .foregroundColor(.white.opacity(0.9))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 170)

                    Button("Less") {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            isExpanded = false
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .underline()
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded = true
                    }
                } label: {
                    Text(attributedDescription(description))
                        .font(Theme.body(14))
                        .foregroundColor(.white.opacity(0.86))
                        .lineSpacing(3)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show the full synopsis")
                .accessibilityIdentifier("book-synopsis")
            }
        }
    }

    private func attributedDescription(_ description: String) -> AttributedString {
        let copy: String
        // Keep the inline action inside three lines at the narrowest width
        // created by the action rail. Expanded mode uses a dedicated scroll area.
        let limit = 105
        let shortened = description.count > limit
            ? String(description.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            : description
        copy = shortened + "  More"

        var attributed = AttributedString(copy)
        if let range = attributed.range(of: "More", options: .backwards) {
            attributed[range].foregroundColor = .white
            attributed[range].font = .systemFont(ofSize: 14, weight: .bold)
            attributed[range].underlineStyle = .single
        }
        return attributed
    }
}

private struct SynopsisFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct BookActionRail: View {
    let onSave: () -> Void
    let onBuy: () -> Void
    let onReadEPUB: () -> Void
    let onSkip: () -> Void
    let isFindingEPUB: Bool

    var body: some View {
        VStack(spacing: 12) {
            action(title: "Save", icon: "heart.fill", action: onSave)
            action(title: "Buy", icon: "cart.fill", action: onBuy)
            action(
                title: "Preview",
                icon: isFindingEPUB ? nil : "book.fill",
                isLoading: isFindingEPUB,
                action: onReadEPUB
            )
            action(title: "Skip", icon: "xmark", action: onSkip)
        }
    }

    private func action(
        title: String,
        icon: String?,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else if let icon {
                        Image(systemName: icon)
                    }
                }
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 28, height: 28)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 54)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}

private struct SimilarBooksBanner: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || isLoading ? 1 : 0.62)
        .accessibilityIdentifier("similar-books-button")
        .background(Color.black.opacity(0.34))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
    }
}

// MARK: - Interactive 3D Book

private struct InteractiveBookCover: View {
    let imageURL: URL?
    let title: String
    let author: String
    let pageCount: Int?

    @State private var image: UIImage?
    @State private var primaryColor = UIColor(red: 0.42, green: 0.28, blue: 0.18, alpha: 1)
    @State private var aspectRatio: CGFloat = 0.66

    var body: some View {
        GeometryReader { geometry in
            BookSceneView(
                coverImage: image,
                primaryColor: primaryColor,
                aspectRatio: aspectRatio,
                pageCount: pageCount,
                textureKey: imageURL?.absoluteString ?? title
            )
            // Keep a wide render surface even for narrow portrait covers. The
            // model preserves the source aspect ratio internally, while the
            // extra canvas prevents rotated corners from being framebuffer-cut.
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: imageURL) {
            await loadCover()
        }
    }

    @MainActor
    private func loadCover() async {
        guard let imageURL else {
            image = fallbackImage()
            return
        }

        if let cached = ImageCache.shared.image(for: imageURL) {
            apply(cached)
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard let loaded = UIImage(data: data) else { return }
            let prepared = await loaded.byPreparingForDisplay() ?? loaded
            ImageCache.shared.insert(prepared, for: imageURL)
            apply(prepared)
        } catch {
            image = fallbackImage()
        }
    }

    private func apply(_ loaded: UIImage) {
        image = loaded
        if loaded.size.height > 0 {
            aspectRatio = loaded.size.width / loaded.size.height
        }
        primaryColor = loaded.averageColor ?? primaryColor
    }

    private func fallbackImage() -> UIImage {
        let size = CGSize(width: 600, height: 900)
        return UIGraphicsImageRenderer(size: size).image { context in
            primaryColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia-Bold", size: 48) ?? .boldSystemFont(ofSize: 48),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let authorAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                .paragraphStyle: paragraph
            ]
            NSString(string: title).draw(in: CGRect(x: 45, y: 260, width: 510, height: 240), withAttributes: titleAttributes)
            NSString(string: author).draw(in: CGRect(x: 45, y: 540, width: 510, height: 80), withAttributes: authorAttributes)
        }
    }
}

private struct BookSceneView: UIViewRepresentable {
    let coverImage: UIImage?
    let primaryColor: UIColor
    let aspectRatio: CGFloat
    let pageCount: Int?
    let textureKey: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        view.clipsToBounds = false
        view.layer.masksToBounds = false
        view.scene = context.coordinator.makeScene()
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didPan(_:))))
        view.isAccessibilityElement = true
        view.accessibilityTraits = .image
        context.coordinator.sceneView = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.updateBook(
            image: coverImage,
            primaryColor: primaryColor,
            aspectRatio: aspectRatio,
            pageCount: pageCount,
            textureKey: textureKey
        )
    }

    final class Coordinator: NSObject {
        weak var sceneView: SCNView?
        private let floatingNode = SCNNode()
        private let bookNode = SCNNode()
        private let pageBlockNode = SCNNode()
        private let frontBoardNode = SCNNode()
        private let backBoardNode = SCNNode()
        private let coverNode = SCNNode()
        private let spineLipNode = SCNNode()
        private var currentTextureKey = ""
        private var currentImage: UIImage?
        private var currentAspectRatio: CGFloat = 0
        private var currentPageCount: Int?
        private let presentationAngle = SCNVector3(-0.16, -0.4, 0.025)

        func makeScene() -> SCNScene {
            let scene = SCNScene()
            scene.rootNode.addChildNode(floatingNode)
            floatingNode.addChildNode(bookNode)
            bookNode.addChildNode(pageBlockNode)
            bookNode.addChildNode(frontBoardNode)
            bookNode.addChildNode(backBoardNode)
            bookNode.addChildNode(coverNode)
            bookNode.addChildNode(spineLipNode)
            bookNode.eulerAngles = presentationAngle

            let camera = SCNCamera()
            camera.fieldOfView = 36
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, 5.0)
            scene.rootNode.addChildNode(cameraNode)

            let keyLight = SCNLight()
            keyLight.type = .omni
            keyLight.intensity = 850
            keyLight.temperature = 5000
            let keyNode = SCNNode()
            keyNode.light = keyLight
            keyNode.position = SCNVector3(-2.5, 3.5, 4)
            scene.rootNode.addChildNode(keyNode)

            let fillLight = SCNLight()
            fillLight.type = .ambient
            fillLight.intensity = 380
            fillLight.color = UIColor(red: 1, green: 0.91, blue: 0.78, alpha: 1)
            let fillNode = SCNNode()
            fillNode.light = fillLight
            scene.rootNode.addChildNode(fillNode)

            let rise = SCNAction.moveBy(x: 0, y: 0.055, z: 0, duration: 2.3)
            rise.timingMode = .easeInEaseOut
            let fall = rise.reversed()
            floatingNode.runAction(.repeatForever(.sequence([rise, fall])), forKey: "float")
            return scene
        }

        func updateBook(
            image: UIImage?,
            primaryColor: UIColor,
            aspectRatio: CGFloat,
            pageCount: Int?,
            textureKey: String
        ) {
            guard currentTextureKey != textureKey
                    || currentImage !== image
                    || currentAspectRatio != aspectRatio
                    || currentPageCount != pageCount
                    || pageBlockNode.geometry == nil else { return }
            currentTextureKey = textureKey
            currentImage = image
            currentAspectRatio = aspectRatio
            currentPageCount = pageCount

            let bookHeight: CGFloat = 2.86
            let bookWidth = bookHeight * aspectRatio
            let pageCountValue = min(max(CGFloat(pageCount ?? 320), 120), 900)
            let pageProgress = (pageCountValue - 120) / 780
            let pageDepth = max(0.14, bookWidth * (0.075 + pageProgress * 0.12))
            let boardThickness = max(0.038, bookWidth * 0.021)
            let boardOverhang = max(0.038, bookWidth * 0.025)

            let boardMaterial = SCNMaterial()
            boardMaterial.diffuse.contents = primaryColor.darkened(by: 0.12)
            boardMaterial.multiply.contents = BookSurfaceTextures.coverGrain
            boardMaterial.multiply.intensity = 0.22
            boardMaterial.roughness.contents = 0.7
            boardMaterial.lightingModel = .physicallyBased

            let spine = SCNMaterial()
            spine.diffuse.contents = primaryColor.darkened(by: 0.18)
            spine.multiply.contents = BookSurfaceTextures.coverGrain
            spine.multiply.intensity = 0.26
            spine.roughness.contents = 0.62

            let pagesMaterial = SCNMaterial()
            pagesMaterial.diffuse.contents = BookSurfaceTextures.pageEdges
            pagesMaterial.diffuse.wrapS = .repeat
            pagesMaterial.diffuse.wrapT = .repeat
            pagesMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 22, 1)
            pagesMaterial.roughness.contents = 0.94

            // Build the book as separate physical layers: an inset page block,
            // two overhanging hardcover boards, a rounded full-depth spine, and
            // an independent artwork plane. This keeps the silhouette believable
            // as thickness changes with page count.
            let pageBlock = SCNBox(
                width: bookWidth - boardOverhang * 1.35,
                height: bookHeight - boardOverhang * 1.55,
                length: pageDepth,
                chamferRadius: 0.018
            )
            pageBlock.chamferSegmentCount = 3
            pageBlock.materials = Array(repeating: pagesMaterial, count: 6)
            pageBlockNode.geometry = pageBlock
            pageBlockNode.position = SCNVector3(Float(boardOverhang * 0.18), 0, 0)

            let frontBoard = SCNBox(
                width: bookWidth,
                height: bookHeight,
                length: boardThickness,
                chamferRadius: 0.026
            )
            frontBoard.chamferSegmentCount = 5
            frontBoard.materials = Array(repeating: boardMaterial, count: 6)
            frontBoardNode.geometry = frontBoard
            frontBoardNode.position = SCNVector3(0, 0, Float(pageDepth / 2 + boardThickness / 2))

            let backBoard = SCNBox(
                width: bookWidth,
                height: bookHeight,
                length: boardThickness,
                chamferRadius: 0.026
            )
            backBoard.chamferSegmentCount = 5
            backBoard.materials = Array(repeating: boardMaterial, count: 6)
            backBoardNode.geometry = backBoard
            backBoardNode.position = SCNVector3(0, 0, Float(-pageDepth / 2 - boardThickness / 2))

            bookNode.castsShadow = true

            let coverPlane = SCNPlane(width: bookWidth - 0.018, height: bookHeight - 0.018)
            let coverMaterial = SCNMaterial()
            coverMaterial.diffuse.contents = image ?? primaryColor
            coverMaterial.diffuse.wrapS = .clamp
            coverMaterial.diffuse.wrapT = .clamp
            coverMaterial.multiply.contents = BookSurfaceTextures.coverGrain
            coverMaterial.multiply.intensity = 0.2
            coverMaterial.multiply.wrapS = .repeat
            coverMaterial.multiply.wrapT = .repeat
            coverMaterial.multiply.contentsTransform = SCNMatrix4MakeScale(8, 12, 1)
            coverMaterial.lightingModel = .constant
            coverMaterial.diffuse.intensity = 0.96
            coverMaterial.isDoubleSided = true
            coverPlane.materials = [coverMaterial]
            coverNode.geometry = coverPlane
            coverNode.position = SCNVector3(0, 0, Float(pageDepth / 2 + boardThickness + 0.002))

            // A raised, color-matched hinge gives the left edge the small lip
            // found on a case-bound book and remains visible from the front.
            let lipWidth = max(0.052, bookWidth * 0.035)
            let lip = SCNBox(
                width: lipWidth,
                height: bookHeight + 0.018,
                length: pageDepth + boardThickness * 2 + 0.028,
                chamferRadius: lipWidth * 0.42
            )
            lip.chamferSegmentCount = 5
            lip.materials = [spine]
            spineLipNode.geometry = lip
            spineLipNode.position = SCNVector3(
                Float(-bookWidth / 2 + lipWidth / 2 - 0.004),
                0,
                0.006
            )
        }

        @objc func didPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = sceneView else { return }
            let translation = gesture.translation(in: view)

            switch gesture.state {
            case .began, .changed:
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0
                bookNode.eulerAngles.x = presentationAngle.x + Float(-translation.y / 210)
                bookNode.eulerAngles.y = presentationAngle.y + Float(translation.x / 150)
                bookNode.eulerAngles.z = presentationAngle.z + Float(translation.x / 1100)
                SCNTransaction.commit()
            case .ended, .cancelled, .failed:
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.9
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.9, 0.22, 1)
                bookNode.eulerAngles = presentationAngle
                SCNTransaction.commit()
            default:
                break
            }
        }
    }
}

private extension UIImage {
    var averageColor: UIColor? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let extent = ciImage.extent
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        guard let output = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }
}

private enum BookSurfaceTextures {
    static let coverGrain: UIImage = {
        let size = CGSize(width: 96, height: 96)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let graphics = context.cgContext
            graphics.setLineWidth(0.65)
            for index in 0..<30 {
                let y = CGFloat((index * 17) % 96) + 0.5
                let alpha = 0.025 + CGFloat(index % 4) * 0.008
                graphics.setStrokeColor(UIColor.black.withAlphaComponent(alpha).cgColor)
                graphics.move(to: CGPoint(x: 0, y: y))
                graphics.addCurve(
                    to: CGPoint(x: 96, y: y + CGFloat((index % 3) - 1)),
                    control1: CGPoint(x: 28, y: y - 1.5),
                    control2: CGPoint(x: 68, y: y + 1.5)
                )
                graphics.strokePath()
            }

            for index in 0..<90 {
                let x = CGFloat((index * 37) % 94) + 1
                let y = CGFloat((index * 61) % 94) + 1
                let radius = CGFloat(index % 3 + 1) * 0.22
                UIColor.black.withAlphaComponent(0.035).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
            }
        }
    }()

    static let pageEdges: UIImage = {
        let size = CGSize(width: 72, height: 72)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.93, green: 0.89, blue: 0.8, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let graphics = context.cgContext
            graphics.setLineWidth(0.55)
            for y in stride(from: CGFloat(1), through: 72, by: 3) {
                graphics.setStrokeColor(UIColor(red: 0.34, green: 0.25, blue: 0.18, alpha: 0.13).cgColor)
                graphics.move(to: CGPoint(x: 0, y: y))
                graphics.addLine(to: CGPoint(x: 72, y: y + 0.4))
                graphics.strokePath()
            }
        }
    }()
}

private extension UIColor {
    func darkened(by amount: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: min(1, saturation * 1.08), brightness: max(0, brightness * (1 - amount)), alpha: alpha)
    }
}

private extension View {
    @ViewBuilder
    func scrollClipDisabledIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollClipDisabled()
        } else {
            self
        }
    }
}
