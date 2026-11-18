import Charts
import SwiftUI

/// The library's dashboard: what Quill has saved you, and which snippets earn their keep.
struct OverviewView: View {
    @Environment(AppState.self) private var state
    @State private var hoveredDay: Date?

    private var store: SnippetStore { state.store }

    private struct Day: Identifiable {
        let date: Date
        let uses: Int
        var id: Date { date }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<14).reversed().map { offset in
            Day(date: calendar.date(byAdding: .day, value: -offset, to: today) ?? today,
                uses: store.uses(onDayOffset: offset))
        }
    }

    /// At about 200 characters a minute, a typical typing speed.
    private var timeSaved: String {
        let seconds = Double(store.totalKeysSaved) / (200.0 / 60.0)
        if seconds < 60 { return "\(Int(seconds)) sec" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        return String(format: "%.1f hr", seconds / 3600)
    }

    var body: some View {
        let days = days
        let weekUses = days.suffix(7).reduce(0) { $0 + $1.uses }
        let top = store.snippets.filter { $0.useCount > 0 }
            .sorted(by: SnippetSortOrder.mostUsed.areInIncreasingOrder)
            .prefix(5)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    StatTile(title: "Expansions", value: store.totalUses.formatted(), detail: "\(weekUses.formatted()) in the last 7 days", symbol: "text.insert", color: .blue)
                    StatTile(title: "Snippets On", value: store.activeSnippets.count.formatted(), detail: "of \(store.snippets.count) in total", symbol: "square.stack.fill", color: .green)
                    StatTile(title: "Groups", value: store.groups.count.formatted(), detail: store.groups.isEmpty ? "make one with ⇧⌘N" : "\(store.groups.filter(\.isEnabled).count) on", symbol: "folder.fill", color: .orange)
                    StatTile(title: "Best Day", value: (days.map(\.uses).max() ?? 0).formatted(), detail: "expansions in one day", symbol: "flame.fill", color: .pink)
                }

                Card(title: "Last 14 Days", subtitle: "Expansions per day") {
                    if days.allSatisfy({ $0.uses == 0 }) {
                        EmptyChartNote(text: "Use a snippet and your daily activity appears here.")
                    } else {
                        dailyChart(days)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Card(title: "Top Snippets", subtitle: "Most expansions") {
                        if top.isEmpty {
                            EmptyChartNote(text: "Nothing used yet.")
                        } else {
                            topChart(Array(top))
                        }
                    }
                    if !store.groups.isEmpty {
                        Card(title: "Groups", subtitle: "Expansions by group") {
                            groupBreakdown
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle("Stats")
    }

    /// The headline: what Quill has saved, on a gradient in the accent colour.
    private var hero: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("All Time")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.totalKeysSaved.formatted())
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("keys saved")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text("About \(timeSaved) of typing · \(statusLine)")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
                .accessibilityHidden(true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .accentColor.opacity(0.3), radius: 14, y: 6)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        switch state.status {
        case .on: "Quill is on"
        case .off: "Quill is off"
        case .pausedUntil(let date): "paused until \(date.formatted(date: .omitted, time: .shortened))"
        case .pausedInApp(let name): "paused in \(name)"
        case .needsAccess: "needs Accessibility access"
        }
    }

    // MARK: Charts

    private func dailyChart(_ days: [Day]) -> some View {
        Chart(days) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Expansions", day.uses),
                width: .ratio(0.62)
            )
            .foregroundStyle(LinearGradient(colors: [.purple, .accentColor], startPoint: .top, endPoint: .bottom))
            .opacity(hoveredDay == nil || Calendar.current.isDate(day.date, inSameDayAs: hoveredDay!) ? 1 : 0.4)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))

            if let hoveredDay, Calendar.current.isDate(day.date, inSameDayAs: hoveredDay) {
                RuleMark(x: .value("Day", day.date, unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text("\(day.uses)")
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.background, in: RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                    }
            }
        }
        .chartXSelection(value: $hoveredDay)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Expansions per day for the last 14 days")
    }

    private func topChart(_ snippets: [Snippet]) -> some View {
        Chart(snippets) { snippet in
            BarMark(
                x: .value("Expansions", snippet.useCount),
                y: .value("Shortcut", snippet.trigger),
                height: .ratio(0.6)
            )
            .foregroundStyle(store.group(for: snippet)?.tint ?? Color.accentColor)
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
            .annotation(position: .trailing, spacing: 6) {
                Text("\(snippet.useCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.callout.monospaced())
            }
        }
        .frame(height: CGFloat(snippets.count) * 30 + 10)
    }

    private var groupBreakdown: some View {
        let rows = store.groups.map { group in
            (group: group, uses: store.snippets(in: group.id).reduce(0) { $0 + $1.useCount })
        }
        let ungrouped = store.snippets(in: nil).reduce(0) { $0 + $1.useCount }
        let maxUses = max(1, (rows.map(\.uses) + [ungrouped]).max() ?? 1)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.group.id) { row in
                GroupBar(name: row.group.name, symbol: row.group.symbol, color: row.group.tint,
                         uses: row.uses, fraction: Double(row.uses) / Double(maxUses))
            }
            if ungrouped > 0 {
                GroupBar(name: "Ungrouped", symbol: "tray", color: .gray,
                         uses: ungrouped, fraction: Double(ungrouped) / Double(maxUses))
            }
        }
    }
}

// MARK: - Pieces

private struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct Card<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct GroupBar: View {
    let name: String
    let symbol: String
    let color: Color
    let uses: Int
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(name, systemImage: symbol)
                    .labelStyle(TintedIconLabelStyle(tint: color))
                    .font(.callout)
                Spacer()
                Text("\(uses)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: max(4, proxy.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

private struct EmptyChartNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
