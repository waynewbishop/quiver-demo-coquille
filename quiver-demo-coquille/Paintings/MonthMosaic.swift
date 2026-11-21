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

    /// One entry as a day lists it.
    struct DayEntry: Equatable, Identifiable {
        let url: URL
        /// The title from the file name, if the entry has one.
        let title: String?
        let tableau: Tableau?
        /// The entry's first line of French.
        let preview: String

        var id: URL { url }
    }

    /// One day of the month.
    struct Day: Equatable, Identifiable {
        let number: Int
        let date: Date
        /// The day's entries, in the order their files were created.
        let entries: [DayEntry]
        /// Whether the day is after today.
        let isFuture: Bool

        var id: Int { number }

        /// The painting the day shows: its first entry's that has one.
        var tableau: Tableau? {
            entries.lazy.compactMap(\.tableau).first
        }
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

    /// Summarizes `entries` for the month holding `date`, judging "future" against `today`.
    init(entries: [Journal.Entry], month date: Date, today: Date = .now, calendar: Calendar = .current) {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        month = start
        let weekday = calendar.component(.weekday, from: start)
        leadingBlanks = (weekday + 5) % 7
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let inMonth = entries
            .filter { calendar.isDate($0.date, equalTo: start, toGranularity: .month) }
            .sorted(by: Self.writtenFirst(calendar: calendar))
        let todayStart = calendar.startOfDay(for: today)

        days = (1...count).compactMap { number in
            guard let dayDate = calendar.date(byAdding: .day, value: number - 1, to: start) else { return nil }
            let onDay = inMonth
                .filter { calendar.isDate($0.date, inSameDayAs: dayDate) }
                .map { DayEntry(url: $0.url, title: $0.title, tableau: $0.tableau, preview: $0.preview) }
            return Day(number: number, date: dayDate, entries: onDay,
                       isFuture: calendar.startOfDay(for: dayDate) > todayStart)
        }
        entryCount = inMonth.count
        let paintings = days.flatMap(\.entries).compactMap(\.tableau)
        paintedCount = paintings.count
        var seen = Set<String>()
        words = paintings.map(\.word).filter { seen.insert($0).inserted }
    }

    /// Orders entries by day, then within a day by when each file was created (its
    /// modification date when the system doesn't say), then by file name.
    private static func writtenFirst(calendar: Calendar) -> (Journal.Entry, Journal.Entry) -> Bool {
        { first, second in
            let firstDay = calendar.startOfDay(for: first.date)
            let secondDay = calendar.startOfDay(for: second.date)
            if firstDay != secondDay { return firstDay < secondDay }
            let firstWritten = first.created ?? first.modified
            let secondWritten = second.created ?? second.modified
            if firstWritten != secondWritten { return firstWritten < secondWritten }
            return first.url.lastPathComponent < second.url.lastPathComponent
        }
    }

    /// The month in French, as in "Novembre 2026".
    func frenchTitle(calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        let name = FrenchCalendar.months[min(max((parts.month ?? 1) - 1, 0), 11)]
        return "\(name.prefix(1).uppercased())\(name.dropFirst()) \(parts.year ?? 2026)"
    }

    /// "12 entries · 10 with a painting"
    var countsLine: String {
        let entries = entryCount == 1 ? "1 entry" : "\(entryCount) entries"
        return "\(entries) · \(paintedCount) with a painting"
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

/// French month names, shared by the postcard and the calendar.
enum FrenchCalendar {
    static let months = [
        "janvier", "février", "mars", "avril", "mai", "juin",
        "juillet", "août", "septembre", "octobre", "novembre", "décembre"
    ]
}

/// The journal's calendar view: the month's paintings day by day and its words.
/// Tapping or clicking a day with one entry opens it; a day with several lists them.
struct MonthMosaicView: View {
    let journal: Journal
    let open: (URL) -> Void

    @State private var month = Date.now

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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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

    /// What a painting cell, a dot and a stacked day mean.
    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems }
            VStack(alignment: .leading, spacing: 6) { legendItems }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    /// The legend's three keys.
    @ViewBuilder
    private var legendItems: some View {
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
        Label {
            Text("Several entries")
        } icon: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
                    .offset(x: 3, y: -3)
                RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.45))
                    .frame(width: 10, height: 10)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.background, lineWidth: 1))
            }
            .frame(width: 13, height: 13, alignment: .bottomLeading)
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
    /// Opens an entry.
    let open: (URL) -> Void

    /// The day whose entries are listed, while its list is up.
    @State private var listedDay: Int?

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

    /// One day: a day with one entry opens it, a day with several lists them.
    @ViewBuilder
    private func cell(_ day: MonthSummary.Day) -> some View {
        let square = DayCell(day: day)
        switch day.entries.count {
        case 0:
            square
                .accessibilityLabel(accessibilityLabel(for: day))
        case 1:
            Button { open(day.entries[0].url) } label: { square }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: day))
                .accessibilityHint("Opens the entry")
        default:
            Button { listedDay = day.number } label: { square }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: day))
                .accessibilityHint("Lists the day's entries")
                .popover(isPresented: isListing(day)) {
                    DayEntriesList(day: day, done: { listedDay = nil }) { url in
                        listedDay = nil
                        open(url)
                    }
                    .presentationCompactAdaptation(.sheet)
                    .presentationDetents([.medium, .large])
                }
        }
    }

    /// Whether `day`'s list is up.
    private func isListing(_ day: MonthSummary.Day) -> Binding<Bool> {
        Binding(get: { listedDay == day.number }, set: { if !$0 { listedDay = nil } })
    }

    /// "16 novembre, Le parc", "8 novembre, entry", "18 novembre, 2 entries, Au bord de l'eau" or "20 novembre".
    private func accessibilityLabel(for day: MonthSummary.Day) -> Text {
        let date = frenchText("\(day.number) \(FrenchCalendar.months[Calendar.current.component(.month, from: day.date) - 1])")
        let count = day.entries.count
        switch (count, day.tableau) {
        case (0, _): return Text(date)
        case (1, let tableau?): return Text("\(date), \(frenchText(tableau.title))")
        case (1, nil): return Text("\(date), entry")
        case (_, let tableau?): return Text("\(date), \(count) entries, \(frenchText(tableau.title))")
        case (_, nil): return Text("\(date), \(count) entries")
        }
    }
}

/// One square of the month grid. A day with several entries shows its first painting
/// with one plain card edge peeking out behind it, however many entries there are, and
/// no number badge; the day's list shows them all.
private struct DayCell: View {
    let day: MonthSummary.Day

    /// How far the card behind a day with several entries peeks out.
    private static let stackInset: CGFloat = 4

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let count = day.entries.count
                    let inset = count > 1 ? Self.stackInset : 0
                    let side = max(geometry.size.width - inset, 0)
                    ZStack(alignment: .topLeading) {
                        if count > 1 {
                            card(Color.secondary.opacity(0.3), side: side)
                                .offset(x: inset)
                        }
                        face
                            .frame(width: side, height: side)
                            .overlay {
                                if count > 1 {
                                    RoundedRectangle(cornerRadius: 7).stroke(.background, lineWidth: 1)
                                }
                            }
                            .offset(y: inset)
                    }
                }
            }
    }

    /// One plain card edge behind the day's face.
    private func card(_ color: Color, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.background, lineWidth: 1))
            .frame(width: side, height: side)
    }

    /// The day's painting or a plain square, its number, and a dot when its entries have no painting.
    private var face: some View {
        Color.clear
            .background {
                if let tableau = day.tableau {
                    Image(tableau.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if day.isFuture {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.2))
                } else if day.entries.count > 1 {
                    // A solid base under the tint, so the card behind doesn't show through.
                    Color.secondary.opacity(0.1).background(.background)
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
                if !day.entries.isEmpty && day.tableau == nil {
                    Circle().fill(Color.brand).frame(width: 6, height: 6).padding(.bottom, 6)
                }
            }
    }
}

/// A day's entries, for a day with several: each with its painting or a dot, its title
/// and its first line, in the order they were written. Choosing one opens it.
private struct DayEntriesList: View {
    let day: MonthSummary.Day
    let done: () -> Void
    let open: (URL) -> Void

    /// The day as the list's title writes it, as in "Mercredi 18 novembre".
    private var title: String {
        let calendar = Calendar.current
        let weekday = Journal.frenchWeekdays[min(max(calendar.component(.weekday, from: day.date) - 1, 0), 6)]
        let month = FrenchCalendar.months[min(max(calendar.component(.month, from: day.date) - 1, 0), 11)]
        return "\(weekday) \(day.number) \(month)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(frenchText(title))
                        .font(.paintingTitle(.title2))
                    Text("\(day.entries.count) entries")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Done", action: done)
                    .fontWeight(.semibold)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(day.entries) { entry in
                        Divider()
                        Button { open(entry.url) } label: { row(entry) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        #if os(macOS)
        // The popover takes the height its header and rows need, up to a cap past which the list scrolls.
        .frame(width: 340)
        .frame(maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    /// One entry: its painting or a dot, the painting's title, the entry's title and its first line.
    private func row(_ entry: MonthSummary.DayEntry) -> some View {
        HStack(spacing: 12) {
            Group {
                if let tableau = entry.tableau {
                    Image(tableau.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.1)
                        .overlay { Circle().fill(Color.brand).frame(width: 6, height: 6) }
                }
            }
            .frame(width: 64, height: 48)
            .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                if let tableau = entry.tableau {
                    Text(frenchText(tableau.title))
                        .font(.paintingTitle(.headline))
                } else {
                    Text("No painting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let title = entry.title {
                    Text(frenchText(title))
                        .font(.footnote.weight(.medium))
                }
                if !entry.preview.isEmpty {
                    Text(frenchText(entry.preview))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the entry")
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
