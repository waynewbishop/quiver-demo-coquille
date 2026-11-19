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

import SwiftUI

/// One month of the journal as a calendar: each day's entry and painting, the counts,
/// and the French words of the month's paintings.
///
/// It's built from the journal's entries as they are, with no store of its own: each
/// entry's date comes from its file name and its painting from its `//: tableau` line.
struct MonthSummary: Equatable {

    /// One day of the month.
    struct Day: Equatable, Identifiable {
        let number: Int
        let date: Date
        /// The entry the day opens: its first with a painting, else its first.
        let entryURL: URL?
        /// That entry's painting, if it has one.
        let tableau: Tableau?
        /// Whether the day is after today.
        let isFuture: Bool

        var id: Int { number }
    }

    /// The first day of the month.
    let month: Date
    /// Blank cells before the first day, since the grid starts on Monday as French calendars do.
    let leadingBlanks: Int
    let days: [Day]
    let entryCount: Int
    let paintedCount: Int
    /// Each painting's French word once, in date order, oldest first.
    let words: [String]

    /// The French weekday initials, Monday first.
    static let weekdayInitials = ["L", "M", "M", "J", "V", "S", "D"]

    /// A mosaic is worth sharing once at least this many days have a painting.
    static let minimumForMosaic = 4

    /// Summarizes `entries` for the month holding `date`, judging "future" against `today`.
    init(entries: [Journal.Entry], month date: Date, today: Date = .now, calendar: Calendar = .current) {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        month = start
        let weekday = calendar.component(.weekday, from: start)
        leadingBlanks = (weekday + 5) % 7
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let inMonth = entries
            .filter { calendar.isDate($0.date, equalTo: start, toGranularity: .month) }
            .sorted { $0.date < $1.date }
        let todayStart = calendar.startOfDay(for: today)

        days = (1...count).compactMap { number in
            guard let dayDate = calendar.date(byAdding: .day, value: number - 1, to: start) else { return nil }
            let onDay = inMonth.filter { calendar.isDate($0.date, inSameDayAs: dayDate) }
            let chosen = onDay.first { $0.tableau != nil } ?? onDay.first
            return Day(number: number, date: dayDate, entryURL: chosen?.url, tableau: chosen?.tableau,
                       isFuture: calendar.startOfDay(for: dayDate) > todayStart)
        }
        entryCount = inMonth.count
        paintedCount = days.filter { $0.tableau != nil }.count
        var seen = Set<String>()
        words = days.compactMap(\.tableau).map(\.word).filter { seen.insert($0).inserted }
    }

    /// The month in French, as in "Novembre 2026".
    func frenchTitle(calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        let name = FrenchCalendar.months[min(max((parts.month ?? 1) - 1, 0), 11)]
        return "\(name.prefix(1).uppercased())\(name.dropFirst()) \(parts.year ?? 2026)"
    }

    /// The month's name in English, as in "November", for the share button, read with
    /// the same calendar as the grid so a time zone can't move it into the month before.
    func englishMonthName(calendar: Calendar = .current) -> String {
        var english = calendar
        english.locale = Locale(identifier: "en")
        return english.monthSymbols[calendar.component(.month, from: month) - 1]
    }

    /// "12 entries · 10 with a painting"
    var countsLine: String {
        let entries = entryCount == 1 ? "1 entry" : "\(entryCount) entries"
        return "\(entries) · \(paintedCount) with a painting"
    }

    /// Whether the month has enough paintings to share as a mosaic.
    var canShareMosaic: Bool {
        paintedCount >= Self.minimumForMosaic
    }

    /// The months the calendar can show, as the first day of each: from the oldest
    /// entry's month to the newest entry's month or this month, whichever is later.
    /// With no entries, only this month.
    static func monthRange(of entries: [Journal.Entry], today: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date> {
        let start = { (date: Date) in calendar.dateInterval(of: .month, for: date)?.start ?? date }
        let thisMonth = start(today)
        let dates = entries.map(\.date)
        let oldest = dates.min().map(start) ?? thisMonth
        let newest = max(dates.max().map(start) ?? thisMonth, thisMonth)
        return min(oldest, thisMonth)...newest
    }
}

/// French month names, shared by the postcard and the mosaic.
enum FrenchCalendar {
    static let months = [
        "janvier", "février", "mars", "avril", "mai", "juin",
        "juillet", "août", "septembre", "octobre", "novembre", "décembre"
    ]
}

/// The journal's calendar view: the month's paintings day by day, its words, and the
/// mosaic to share. Tapping or clicking a day with an entry opens it.
struct MonthMosaicView: View {
    let journal: Journal
    let open: (URL) -> Void

    @State private var month = Date.now
    @State private var mosaicFile: URL?

    private var summary: MonthSummary {
        MonthSummary(entries: journal.entries, month: month)
    }

    /// The months there are to show, from the oldest entry to the newest or this month.
    private var range: ClosedRange<Date> {
        MonthSummary.monthRange(of: journal.entries)
    }

    /// The first day of the month on show.
    private var monthStart: Date {
        Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
    }

    /// Whether the calendar is on this month.
    private var isThisMonth: Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        let summary = summary
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(summary)
                MosaicGrid(summary: summary, open: open)
                legend
                if !summary.words.isEmpty {
                    WordChips(words: summary.words)
                }
                if summary.canShareMosaic {
                    shareButton(summary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .task(id: summary) {
            mosaicFile = summary.canShareMosaic ? MosaicRenderer.file(for: summary) : nil
        }
    }

    /// The label, the month in French with arrows to move between months, and the counts.
    private func header(_ summary: MonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LE MOIS EN TABLEAUX")
                .font(.plexMono(12, relativeTo: .caption))
                .tracking(0.96)
                .foregroundStyle(Color.brand)
            HStack(alignment: .firstTextBaseline) {
                // Tapping the month brings the calendar back to this month after browsing.
                Button {
                    month = .now
                } label: {
                    Text(frenchText(summary.frenchTitle()))
                        .font(.paintingTitle(.largeTitle))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .buttonStyle(.plain)
                .disabled(isThisMonth)
                .accessibilityHint(isThisMonth ? "" : "Goes back to this month")
                #if os(macOS)
                .help(isThisMonth ? "" : "Go back to this month")
                #endif
                Spacer(minLength: 8)
                Button("Previous month", systemImage: "chevron.left") { step(-1) }
                    .disabled(monthStart <= range.lowerBound)
                Button("Next month", systemImage: "chevron.right") { step(1) }
                    .disabled(monthStart >= range.upperBound)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            Text(summary.countsLine)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// What a painting cell and a dot mean.
    private var legend: some View {
        HStack(spacing: 14) {
            Label {
                Text("Entry with a painting")
            } icon: {
                RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.45)).frame(width: 12, height: 12)
            }
            Label {
                Text("Entry, no painting")
            } icon: {
                Circle().fill(Color.brand).frame(width: 6, height: 6)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    /// Shares the month as one 1800 × 2400 image.
    @ViewBuilder
    private func shareButton(_ summary: MonthSummary) -> some View {
        if let mosaicFile {
            ShareLink(item: mosaicFile) {
                Text("Share \(summary.englishMonthName()) as a mosaic")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Moves to the month `offset` months away.
    private func step(_ offset: Int) {
        month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month
    }
}

/// The month grid: weekday initials, then one square per day, a painting where there is one.
struct MosaicGrid: View {
    let summary: MonthSummary
    /// Opens a day's entry, or `nil` in the shared image, where nothing is tappable.
    var open: ((URL) -> Void)?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
            ForEach(Array(MonthSummary.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .font(.plexMono(11, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            ForEach(0..<summary.leadingBlanks, id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
            ForEach(summary.days) { day in
                cell(day)
            }
        }
    }

    /// One day: its painting or a plain square, its number, and a dot for an entry without a painting.
    @ViewBuilder
    private func cell(_ day: MonthSummary.Day) -> some View {
        let square = DayCell(day: day)
        if let url = day.entryURL, let open {
            Button { open(url) } label: { square }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: day))
                .accessibilityHint("Opens the entry")
        } else {
            square
                .accessibilityLabel(accessibilityLabel(for: day))
        }
    }

    /// "16 novembre, Le parc", "8 novembre, entry" or "20 novembre".
    private func accessibilityLabel(for day: MonthSummary.Day) -> Text {
        let date = "\(day.number) \(FrenchCalendar.months[Calendar.current.component(.month, from: day.date) - 1])"
        if let tableau = day.tableau { return Text("\(frenchText(date)), \(frenchText(tableau.title))") }
        if day.entryURL != nil { return Text("\(frenchText(date)), entry") }
        return Text(frenchText(date))
    }
}

/// One square of the month grid.
private struct DayCell: View {
    let day: MonthSummary.Day

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background {
                if let tableau = day.tableau {
                    Image(tableau.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if day.isFuture {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.2))
                } else {
                    Color.secondary.opacity(0.1)
                }
            }
            .clipShape(.rect(cornerRadius: 7))
            .overlay(alignment: .topLeading) {
                Text("\(day.number)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(day.tableau != nil ? Color.white : (day.isFuture ? Color.secondary.opacity(0.6) : Color.secondary))
                    .shadow(color: day.tableau != nil ? .black.opacity(0.6) : .clear, radius: 1.5, y: 1)
                    .padding(.leading, 4)
                    .padding(.top, 3)
            }
            .overlay(alignment: .bottom) {
                if day.entryURL != nil && day.tableau == nil {
                    Circle().fill(Color.brand).frame(width: 6, height: 6).padding(.bottom, 6)
                }
            }
    }
}

/// The month's painting words as chips.
private struct WordChips: View {
    let words: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Words from your paintings")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Every painting teaches one French word. These are the words from this month's paintings, in the order you wrote them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            FlowLayout(spacing: 6) {
                ForEach(words, id: \.self) { word in
                    Text(frenchText(word))
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(Color.brand)
                        .background(Color.brand.opacity(0.12), in: .capsule)
                }
            }
        }
    }
}

/// Lays out views in rows, wrapping to the next row when one is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    /// The height of the rows the subviews wrap into within the proposed width.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, in: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    /// Places each subview at its row and offset.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    /// Groups subviews into rows that fit `width`.
    private func arrange(_ subviews: Subviews, in width: CGFloat) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: [Int] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var y: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.isEmpty && rowWidth + spacing + size.width > width {
                rows.append((current, y, rowWidth, rowHeight))
                y += rowHeight + spacing
                current = []
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (current.isEmpty ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
            current.append(index)
        }
        if !current.isEmpty { rows.append((current, y, rowWidth, rowHeight)) }
        return rows
    }
}

/// The month as a shareable image: 600 × 800 points, drawn at 1800 × 2400 pixels.
struct MosaicCard: View {
    let summary: MonthSummary

    static let size = CGSize(width: 600, height: 800)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LE MOIS EN TABLEAUX")
                    .font(.plexMono(13))
                    .tracking(1)
                    .foregroundStyle(Color.brand)
                Text(frenchText(summary.frenchTitle()))
                    .font(.cormorant(fixed: 58))
                Text(summary.countsLine)
                    .font(.plexSans(15))
                    .foregroundStyle(.secondary)
            }
            MosaicGrid(summary: summary)
            if !summary.words.isEmpty {
                WordChips(words: summary.words)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text(frenchText("Écrit avec Coquille"))
                    .font(.plexSans(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(36)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(red: 0.980, green: 0.976, blue: 0.961))
        .foregroundStyle(Color(red: 0.078, green: 0.129, blue: 0.239))
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .light)
    }
}

/// Draws a month's mosaic to a JPEG file for sharing.
@MainActor
enum MosaicRenderer {

    /// Writes the mosaic for `summary` to a temporary file named for the month, or `nil` if it can't be drawn.
    static func file(for summary: MonthSummary) -> URL? {
        guard let data = PostcardRenderer.jpeg(of: MosaicCard(summary: summary)) else { return nil }
        guard let folder = try? PostcardRenderer.newExportFolder() else { return nil }
        let url = folder.appending(path: "\(summary.frenchTitle()) en tableaux.jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
