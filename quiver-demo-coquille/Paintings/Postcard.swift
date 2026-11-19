// Copyright 2026 Wayne W Bishop. All rights reserved.
//
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use this
// file except in compliance with the License. You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
// ANY KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// What a postcard shows: the entry's painting, its French as written, the English
/// translation if there is one, and the entry's date for the postmark.
struct PostcardContent: Equatable {
    let tableau: Tableau
    /// The French with notes, markers and the date heading taken out.
    let french: String
    /// The English pane's translation, or `nil` while there isn't one.
    let english: String?
    let date: Date

    /// The French text for the back: `text` without its notes, review markers and the
    /// date heading a new entry starts with, since the postmark carries the date.
    static func backText(from text: String) -> String {
        var lines = Notes.removed(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        lines = Array(lines.drop(while: \.isEmpty))
        if let first = lines.first, Journal.isDateLine(first) {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The date as the back's heading writes it, as in "LUNDI 16 NOVEMBRE 2026".
    func heading(calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let weekday = Journal.frenchWeekdays[min(max((parts.weekday ?? 1) - 1, 0), 6)]
        let day = parts.day == 1 ? "1er" : "\(parts.day ?? 1)"
        let month = FrenchCalendar.months[min(max((parts.month ?? 1) - 1, 0), 11)]
        return "\(weekday) \(day) \(month) \(parts.year ?? 2026)".uppercased()
    }

    /// The postmark's two lines: the weekday, then the date as "16·11·26".
    func postmark(calendar: Calendar = .current) -> (weekday: String, date: String) {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let weekday = Journal.frenchWeekdays[min(max((parts.weekday ?? 1) - 1, 0), 6)].uppercased()
        let digits = [parts.day ?? 1, parts.month ?? 1, (parts.year ?? 2026) % 100]
            .map { String(format: "%02d", $0) }
        return (weekday, digits.joined(separator: "·"))
    }
}

/// The postcard's two sides.
enum PostcardSide: String, CaseIterable, Identifiable {
    case front
    case back

    var id: Self { self }

    /// The side's name in English and French, as the picker shows it.
    var title: String {
        switch self {
        case .front: "Front · Recto"
        case .back: "Back · Verso"
        }
    }
}

/// One side of a postcard, drawn at 600 × 400 points: 6 × 4 inches at 100 points per inch.
///
/// Its colors and type sizes are fixed, since it becomes an image others see.
struct PostcardView: View {
    let content: PostcardContent
    let side: PostcardSide
    var showsWord = true
    var showsEnglish = true

    static let size = CGSize(width: 600, height: 400)

    private static let paper = Color(red: 0.984, green: 0.973, blue: 0.945)
    private static let ink = Color(red: 0.122, green: 0.176, blue: 0.333)
    private static let muted = Color(red: 0.357, green: 0.392, blue: 0.471)
    private static let rule = Color(red: 0.725, green: 0.682, blue: 0.596)

    var body: some View {
        Group {
            switch side {
            case .front: front
            case .back: back
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .light)
    }

    /// The painting edge to edge inside a white border, with its title in the corner.
    private var front: some View {
        Image(content.tableau.imageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.size.width - 28, height: Self.size.height - 28)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(frenchText(content.tableau.title))
                        .font(.cormorant(fixed: 27))
                        .foregroundStyle(Color(white: 0.08))
                    if showsWord {
                        Text("\(Text(frenchText(content.tableau.word)).foregroundStyle(Color.brand).fontWeight(.semibold)) · \(content.tableau.wordEnglish)")
                            .font(.plexSans(11))
                            .foregroundStyle(Self.muted)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Self.paper.opacity(0.93), in: .rect(cornerRadius: 3))
                .padding(14)
            }
            .padding(14)
            .background(.white)
    }

    /// The French on the left, then the stamp, the postmark and the address lines.
    private var back: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(content.heading())
                    .font(.plexMono(9.5))
                    .tracking(0.8)
                    .foregroundStyle(Self.muted)
                Text(frenchText(content.french))
                    .font(.cormorant(fixed: 21, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(Self.ink)
                    .minimumScaleFactor(0.5)
                if showsEnglish, let english = content.english {
                    WavyRule()
                        .stroke(Self.rule, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                        .frame(width: 72, height: 8)
                        .padding(.vertical, 2)
                        .accessibilityHidden(true)
                    Text(english)
                        .font(.plexSans(10.5).italic())
                        .lineSpacing(2)
                        .foregroundStyle(Self.muted)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Self.rule.opacity(0.7))
                .frame(width: 1)

            VStack(alignment: .trailing, spacing: 0) {
                PaintingStamp(tableau: content.tableau, width: 112)
                    .overlay(alignment: .bottomLeading) { postmark.offset(x: -54, y: 26) }
                VStack(spacing: 18) {
                    addressLine(label: "Pour :")
                    addressLine(label: nil)
                    addressLine(label: nil)
                }
                .padding(.top, 44)
                Spacer(minLength: 0)
                Text(frenchText("Écrit avec Coquille"))
                    .font(.plexSans(8.5))
                    .foregroundStyle(Self.muted)
            }
            .frame(width: 200)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(Self.paper)
    }

    /// The round postmark with the entry's weekday and date, set at an angle over the stamp.
    private var postmark: some View {
        let mark = content.postmark()
        return VStack(spacing: 1) {
            Text(frenchText(mark.weekday))
                .font(.plexMono(7.5))
                .tracking(0.5)
            Text(mark.date)
                .font(.plexMono(9.5, weight: .medium))
        }
        .foregroundStyle(Self.ink.opacity(0.7))
        .frame(width: 70, height: 70)
        .overlay(Circle().strokeBorder(Self.ink.opacity(0.55), lineWidth: 1.5))
        .rotationEffect(.degrees(-12))
    }

    /// One ruled address line, with "Pour :" on the first.
    private func addressLine(label: String?) -> some View {
        HStack(alignment: .lastTextBaseline) {
            if let label {
                Text(frenchText(label))
                    .font(.cormorant(fixed: 17, weight: .medium))
                    .foregroundStyle(Self.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 22, alignment: .bottom)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Self.rule).frame(height: 1)
        }
    }
}

/// Draws postcard sides as JPEG images, 1800 × 1200 pixels each.
///
/// SwiftUI draws each side on the main actor; encoding the JPEG and writing its file run off it.
@MainActor
enum PostcardRenderer {

    /// Three pixels per point, so 600 × 400 points become 1800 × 1200 pixels: 6 × 4 in at 300 dpi.
    static let scale = 3.0

    /// A postcard side drawn at `scale` into a finished bitmap, or `nil` if it can't be drawn.
    ///
    /// The bitmap is filled in here, on the main actor, so encoding it later never draws views off it.
    static func bitmap(of view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// The JPEG of a finished bitmap, or `nil` if it can't be encoded; safe off the main actor.
    nonisolated static func jpeg(from image: CGImage, quality: Double = 0.85) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The JPEG of a postcard side, drawn at `scale`, or `nil` if it can't be drawn.
    static func jpeg(of view: some View, quality: Double = 0.85) -> Data? {
        bitmap(of: view).flatMap { jpeg(from: $0, quality: quality) }
    }

    /// The temporary folder that holds every export, one subfolder each.
    nonisolated static var exportsFolder: URL {
        FileManager.default.temporaryDirectory.appending(path: "Postcards", directoryHint: .isDirectory)
    }

    /// A new, empty temporary folder for one export, so a later redraw never replaces
    /// a file that's already being shared.
    nonisolated static func newExportFolder() throws -> URL {
        let folder = exportsFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Removes the exports of earlier launches; called at launch, before any share could be reading one.
    nonisolated static func removeOldExports() {
        try? FileManager.default.removeItem(at: exportsFolder)
    }

    /// The JPEG of one postcard side, or an error if it can't be drawn.
    static func image(of content: PostcardContent, side: PostcardSide, showsWord: Bool, showsEnglish: Bool) throws -> Data {
        let view = PostcardView(content: content, side: side, showsWord: showsWord, showsEnglish: showsEnglish)
        guard let data = jpeg(of: view) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    /// The file name of one side, as in "Le parc – verso.jpg".
    static func fileName(of content: PostcardContent, side: PostcardSide) -> String {
        "\(content.tableau.title) – \(side == .back ? "verso" : "recto").jpg"
    }

    /// Draws the chosen sides and writes them to temporary JPEG files for sharing, back first,
    /// named for the painting; only the drawing holds the main actor.
    static func files(for content: PostcardContent, sides: [PostcardSide], showsWord: Bool, showsEnglish: Bool) async throws -> [URL] {
        let folder = try newExportFolder()
        let bitmaps = try sides.map { side in
            let view = PostcardView(content: content, side: side, showsWord: showsWord, showsEnglish: showsEnglish)
            guard let bitmap = bitmap(of: view) else { throw CocoaError(.fileWriteUnknown) }
            return bitmap
        }
        let urls = sides.map { folder.appending(path: fileName(of: content, side: $0)) }
        try await write(bitmaps, to: urls)
        return urls
    }

    /// Encodes each bitmap as a JPEG and writes it to the matching URL, off the main actor.
    @concurrent
    nonisolated private static func write(_ bitmaps: [CGImage], to urls: [URL]) async throws {
        for (bitmap, url) in zip(bitmaps, urls) {
            guard let data = jpeg(from: bitmap) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        }
    }
}

/// One postcard side for the share sheet: the file the sheet prepared, or drawn when the
/// learner shares it if that file isn't ready yet.
nonisolated struct PostcardShare: Transferable, Sendable {
    let content: PostcardContent
    let side: PostcardSide
    let showsWord: Bool
    let showsEnglish: Bool
    /// The file already written for this side and these options, if it's ready.
    var prepared: URL?

    /// Hands over the side as a JPEG file, the prepared one when it's there.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpeg) { share in
            if let prepared = share.prepared, FileManager.default.fileExists(atPath: prepared.path) {
                return SentTransferredFile(prepared)
            }
            return SentTransferredFile(try await share.file())
        }
    }

    /// Draws the side and writes it to its own temporary folder.
    @MainActor
    private func file() async throws -> URL {
        try await PostcardRenderer.files(for: content, sides: [side], showsWord: showsWord, showsEnglish: showsEnglish)[0]
    }
}

/// A postcard image for the Mac's Save Images panel.
struct PostcardImageFile: FileDocument {
    static let readableContentTypes: [UTType] = [.jpeg]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    /// Writes the JPEG as it is.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The Share as Postcard sheet: a preview with Front and Back, the two options, the
/// choice of back only or both sides, then Share, and Save Images on the Mac.
///
/// Once the sheet is up, it draws both sides for the current options and writes them to
/// files, again after each change, so Share hands the share sheet finished images.
struct PostcardSheet: View {
    let content: PostcardContent

    @Environment(\.dismiss) private var dismiss
    @State private var side = PostcardSide.back
    @State private var showsEnglish = true
    @State private var showsWord = true
    @State private var sendsBothSides = false
    @State private var problem: Problem?
    /// Both sides, written for the options they were drawn with.
    @State private var prepared: PreparedSides?
    #if os(macOS)
    @State private var exporting: [PostcardImageFile] = []
    #endif

    /// What went wrong, for the alert.
    private struct Problem {
        let title: String
        let message: String
    }

    /// The two options that change what a side looks like.
    private struct Options: Hashable {
        let showsWord: Bool
        let showsEnglish: Bool
    }

    /// Both sides' files and the options they were drawn with.
    private struct PreparedSides {
        let options: Options
        let files: [PostcardSide: URL]
    }

    /// The options as they're set now.
    private var options: Options {
        Options(showsWord: showsWord, showsEnglish: showsEnglish)
    }

    /// The sides that are shared and saved.
    private var sides: [PostcardSide] {
        sendsBothSides ? [.back, .front] : [.back]
    }

    /// The prepared file of `side`, if it was drawn with the options as they're set now.
    private func preparedFile(for side: PostcardSide) -> URL? {
        guard let prepared, prepared.options == options else { return nil }
        return prepared.files[side]
    }

    /// The chosen sides as the share sheet takes them, with their prepared files when ready.
    private var shares: [PostcardShare] {
        sides.map { side in
            PostcardShare(content: content, side: side, showsWord: showsWord, showsEnglish: showsEnglish,
                          prepared: preparedFile(for: side))
        }
    }

    /// Draws both sides for the current options and writes them to files, after a pause that
    /// lets the sheet finish opening and a run of option changes settle.
    private func prepareFiles() async {
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let options = options
        let sides: [PostcardSide] = [.back, .front]
        guard let urls = try? await PostcardRenderer.files(for: content, sides: sides,
                                                           showsWord: options.showsWord, showsEnglish: options.showsEnglish),
              !Task.isCancelled else { return }
        prepared = PreparedSides(options: options, files: Dictionary(uniqueKeysWithValues: zip(sides, urls)))
    }

    var body: some View {
        NavigationStack {
            filling(layout)
                .navigationTitle("Share as Postcard")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task(id: options) { await prepareFiles() }
        }
        #if os(macOS)
        .frame(width: 720, height: 460)
        .fileExporter(isPresented: isExporting, documents: exporting, contentType: .jpeg) { result in
            exporting = []
            if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                problem = Problem(title: "The images couldn't be saved", message: error.localizedDescription)
            }
        }
        #endif
        .alert(problem?.title ?? "", isPresented: showsProblem) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem?.message ?? "")
        }
    }

    /// The preview beside the controls on the Mac, above them on iPhone and iPad.
    ///
    /// The preview is at most 360 points wide: about 720 pixels on a Retina screen, close
    /// to the 700-pixel paintings, so it shows them sharp instead of stretched.
    private var layout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                preview.frame(width: Self.previewWidth)
                controls.frame(width: 264)
            }
            .padding(24)
            .frame(minWidth: 700)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    preview
                        .frame(maxWidth: Self.previewWidth)
                        .frame(maxWidth: .infinity)
                    controls
                }
                .padding(20)
            }
        }
    }

    /// The widest the preview gets.
    private static let previewWidth: CGFloat = 360

    /// Wraps the sheet's layout so it fills the sheet.
    private func filling(_ view: some View) -> some View {
        view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The chosen side, scaled to fit, with a shadow like a card on a table.
    private var preview: some View {
        PostcardView(content: content, side: side, showsWord: showsWord, showsEnglish: showsEnglish)
            .id(side)
            .transition(.opacity)
            .scaleToFit(PostcardView.size)
            .clipShape(.rect(cornerRadius: 4))
            .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
            .animation(.easeInOut(duration: 0.25), value: side)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(side == .front
                ? Text("Postcard front: \(frenchText(content.tableau.title))")
                : Text("Postcard back: \(frenchText(content.french))"))
    }

    /// The side, the options, what to send, and the actions.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Side", selection: $side) {
                ForEach(PostcardSide.allCases) { side in
                    Text(side.title).tag(side)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("English translation on the back", isOn: $showsEnglish)
                    .disabled(content.english == nil)
                if content.english == nil {
                    Text("Turn on English in the editor to include the translation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Toggle("French word on the front", isOn: $showsWord)
            }

            Picker("Send", selection: $sendsBothSides) {
                Text("Back only").tag(false)
                Text("Both sides").tag(true)
            }
            .pickerStyle(.segmented)

            ShareLink(items: shares) { share in
                SharePreview(PostcardRenderer.fileName(of: content, side: share.side),
                             image: Image(content.tableau.imageName))
            } label: {
                Label("Share Postcard", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)

            #if os(macOS)
            Button(action: saveImages) {
                Text("Save Images…")
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            #endif

            Text(sendsBothSides
                 ? "Shares two images, the back and the front, 1800 × 1200 pixels each."
                 : "Shares one image of the back, 1800 × 1200 pixels, with the painting as its stamp.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    #if os(macOS)
    /// Opens the save panel with the chosen sides, prepared or drawn now, or says why they couldn't be drawn.
    private func saveImages() {
        do {
            exporting = try sides.map { side in
                if let url = preparedFile(for: side), let data = try? Data(contentsOf: url) {
                    return PostcardImageFile(data: data)
                }
                return PostcardImageFile(data: try PostcardRenderer.image(of: content, side: side,
                                                                          showsWord: showsWord, showsEnglish: showsEnglish))
            }
        } catch {
            problem = Problem(title: "The postcard couldn't be made", message: error.localizedDescription)
        }
    }
    #endif

    private var showsProblem: Binding<Bool> {
        Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
    }

    #if os(macOS)
    private var isExporting: Binding<Bool> {
        Binding(get: { !exporting.isEmpty }, set: { if !$0 { exporting = [] } })
    }
    #endif
}

private extension View {
    /// Scales a view drawn at `size` down to the width it's offered, keeping its shape.
    func scaleToFit(_ size: CGSize) -> some View {
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    self.scaleEffect(geometry.size.width / size.width, anchor: .topLeading)
                }
            }
            .clipped()
    }
}

/// A short wavy line, the delimiter between the French and its English on a postcard's back.
nonisolated struct WavyRule: Shape {
    /// How many full waves fit across the line.
    var waves = 4.0

    /// A sine wave across `rect`, centred on its middle.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 64
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let x = rect.minX + rect.width * progress
            let y = rect.midY + sin(progress * waves * 2 * .pi) * rect.height / 2
            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}
