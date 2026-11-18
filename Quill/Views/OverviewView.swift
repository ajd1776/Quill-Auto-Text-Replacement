import Charts
import SwiftUI

/// The Stats page: what Quill saves you, when and where you use it, and what could be tidied up.
struct OverviewView: View {
    @Environment(AppState.self) private var state
    @AppStorage("statsPeriod") private var period = 14
    @State private var hoveredDay: Date?

    private var store: SnippetStore { state.store }

    var body: some View {
        let days = QuillStats.days(period, from: store.dailyUses)
        let periodUses = days.reduce(0) { $0 + $1.uses }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    StatTile(title: "Keys Saved", value: store.totalKeysSaved.formatted(),
                             detail: "About \(QuillStats.durationText(QuillStats.timeSaved(keys: store.totalKeysSaved))) of typing",
                             symbol: "keyboard", color: .purple)
                    StatTile(title: "Expansions", value: periodUses.formatted(),
                             detail: "in \(period) days · \(store.totalUses.formatted()) in all", symbol: "text.insert", color: .blue)
                    StatTile(title: "Streak", value: streakText,
                             detail: "Best day: \(QuillStats.bestDay(store.dailyUses).formatted()) expansions", symbol: "flame", color: .orange)
                    StatTile(title: "Snippets On", value: store.activeSnippets.count.formatted(),
                             detail: "of \(store.snippets.count) · \(store.groups.count) \(store.groups.count == 1 ? "group" : "groups")",
                             symbol: "checkmark.circle", color: .green)
                }

                Card(title: "Expansions per Day", subtitle: "Last \(period) days") {
                    if periodUses == 0 {
                        EmptyNote(text: "Use a snippet and your daily activity appears here.")
                    } else {
                        dailyChart(days, average: Double(periodUses) / Double(max(period, 1)))
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Card(title: "Busiest Hours", subtitle: "From your history") {
                        hoursChart
                    }
                    Card(title: "Top Apps", subtitle: "Where you expand most") {
                        topApps
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Card(title: "Top Snippets", subtitle: "Most expansions") {
                        topSnippets
                    }
                    Card(title: "Groups", subtitle: "Expansions by group") {
                        groupBreakdown
                    }
                }

                tidyUp
            }
            .padding(24)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Stats")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stats")
                    .font(.system(size: 26, weight: .bold))
                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Period", selection: $period) {
                Text("7 Days").tag(7)
                Text("14 Days").tag(14)
                Text("30 Days").tag(30)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("stats-period")
        }
    }

    private var streakText: String {
        let streak = QuillStats.streak(store.dailyUses)
        return streak == 1 ? "1 day" : "\(streak) days"
    }

    private var statusLine: String {
        switch state.status {
        case .on: "Quill is on"
        case .off: "Quill is off"
        case .pausedUntil(let date): "Paused until \(date.formatted(date: .omitted, time: .shortened))"
        case .pausedInApp(let name): "Paused in \(name)"
        case .needsAccess: "Quill needs Accessibility access"
        }
    }

    // MARK: Charts

    private func dailyChart(_ days: [QuillStats.Day], average: Double) -> some View {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Expansions", day.uses), width: .ratio(0.62))
                    .foregroundStyle(Color.accentColor)
                    .opacity(hoveredDay == nil || Calendar.current.isDate(day.date, inSameDayAs: hoveredDay!) ? 1 : 0.4)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
            }
            RuleMark(y: .value("Average", average))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Average \(average.formatted(.number.precision(.fractionLength(1))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            if let hoveredDay, let day = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: hoveredDay) }) {
                RuleMark(x: .value("Day", day.date, unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text("\(day.uses)").font(.callout.weight(.semibold)).monospacedDigit()
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                    }
            }
        }
        .chartXSelection(value: $hoveredDay)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: period > 14 ? 5 : 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .frame(height: 190)
        .accessibilityLabel("Expansions per day for the last \(period) days")
    }

    @ViewBuilder
    private var hoursChart: some View {
        let hours = QuillStats.hours(state.history.entries)
        if hours.allSatisfy({ $0 == 0 }) {
            EmptyNote(text: state.keepsHistory ? "Expand a few snippets to see when you use Quill." : "Turn on history in Settings to see this.")
        } else {
            let peak = hours.firstIndex(of: hours.max() ?? 0) ?? 0
            VStack(alignment: .leading, spacing: 8) {
                Chart(Array(hours.enumerated()), id: \.offset) { hour, uses in
                    BarMark(x: .value("Hour", hour), y: .value("Expansions", uses), width: .fixed(10))
                        .foregroundStyle(hour == peak ? Color.orange : Color.orange.opacity(0.45))
                }
                .chartXScale(domain: -0.5...23.5)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18]) { value in
                        AxisValueLabel { Text(hourLabel(value.as(Int.self) ?? 0)) }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 120)
                Text("Busiest around \(hourLabel(peak))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Busiest around \(hourLabel(peak))")
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    @ViewBuilder
    private var topApps: some View {
        let apps = QuillStats.topApps(state.history.entries)
        if apps.isEmpty {
            EmptyNote(text: "Apps you expand snippets in appear here.")
        } else {
            let most = max(apps.first?.uses ?? 1, 1)
            VStack(spacing: 10) {
                ForEach(apps) { app in
                    BarRow(title: app.name, value: app.uses, fraction: Double(app.uses) / Double(most), color: .blue) {
                        AppIconView(bundleID: app.bundleID, size: 18)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var topSnippets: some View {
        let top = store.snippets.filter { $0.useCount > 0 }.sorted(by: SnippetSortOrder.mostUsed.areInIncreasingOrder).prefix(5)
        if top.isEmpty {
            EmptyNote(text: "Nothing used yet.")
        } else {
            let most = max(top.first?.useCount ?? 1, 1)
            VStack(spacing: 10) {
                ForEach(Array(top)) { snippet in
                    let group = store.group(for: snippet)
                    Button {
                        state.page = .snippets
                        state.selection = [.snippet(snippet.id)]
                    } label: {
                        BarRow(title: snippet.trigger, monospaced: true, value: snippet.useCount,
                               fraction: Double(snippet.useCount) / Double(most), color: group?.tint ?? .accentColor) {
                            SnippetIcon(symbol: snippet.symbol ?? group?.symbol, color: group?.tint, size: 18)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show \u{201C}\(snippet.trigger)\u{201D}")
                }
            }
        }
    }

    @ViewBuilder
    private var groupBreakdown: some View {
        let rows = store.groups.map { group in
            (group: group, uses: store.snippets(in: group.id).reduce(0) { $0 + $1.useCount })
        }
        let ungrouped = store.snippets(in: nil).reduce(0) { $0 + $1.useCount }
        let most = max(1, (rows.map(\.uses) + [ungrouped]).max() ?? 1)
        if rows.isEmpty && ungrouped == 0 {
            EmptyNote(text: "Make groups to see how each one is used.")
        } else {
            VStack(spacing: 10) {
                ForEach(rows, id: \.group.id) { row in
                    BarRow(title: row.group.name, value: row.uses, fraction: Double(row.uses) / Double(most), color: row.group.tint) {
                        SnippetIcon(symbol: row.group.symbol, color: row.group.tint, size: 18)
                    }
                }
                if ungrouped > 0 {
                    BarRow(title: "Ungrouped", value: ungrouped, fraction: Double(ungrouped) / Double(most), color: .gray) {
                        SnippetIcon(symbol: "tray", color: .gray, size: 18)
                    }
                }
            }
        }
    }

    // MARK: Tidy up

    @ViewBuilder
    private var tidyUp: some View {
        let unused = QuillStats.unused(store.snippets)
        let problems = store.snippets.compactMap { snippet in store.problem(with: snippet).map { (snippet, $0) } }
        Card(title: "Tidy Up", subtitle: "Snippets that need a look") {
            if unused.isEmpty && problems.isEmpty {
                Label("Nothing to tidy up. Every snippet is working and in use.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                VStack(spacing: 0) {
                    ForEach(problems, id: \.0.id) { snippet, problem in
                        TidyRow(snippet: snippet, detail: problem, symbol: "exclamationmark.triangle.fill", color: .orange)
                        Divider()
                    }
                    ForEach(unused.prefix(6)) { snippet in
                        TidyRow(snippet: snippet,
                                detail: "Never used · made \(snippet.created.formatted(.relative(presentation: .named)))",
                                symbol: "moon.zzz.fill", color: .secondary)
                        Divider()
                    }
                }
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BarRow<Icon: View>: View {
    let title: String
    var monospaced = false
    let value: Int
    let fraction: Double
    let color: Color
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                icon
                Text(title)
                    .font(monospaced ? .callout.monospaced() : .callout)
                    .lineLimit(1)
                Spacer()
                Text(value.formatted())
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
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TidyRow: View {
    let snippet: Snippet
    let detail: String
    let symbol: String
    let color: Color
    @Environment(AppState.self) private var state

    var body: some View {
        let group = state.store.group(for: snippet)
        HStack(spacing: 10) {
            SnippetIcon(symbol: snippet.symbol ?? group?.symbol, color: group?.tint, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(snippet.trigger.isEmpty ? "New Snippet" : snippet.trigger)
                    .font(.callout.monospaced().weight(.semibold))
                Label(detail, systemImage: symbol)
                    .font(.caption)
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            Spacer()
            if snippet.isEnabled {
                Button("Turn Off") { state.store.setEnabled(snippet.id, false) }
                    .controlSize(.small)
            }
            Button("Show") {
                state.page = .snippets
                state.selection = [.snippet(snippet.id)]
            }
            .controlSize(.small)
        }
        .padding(.vertical, 7)
    }
}

/// An app's icon from its bundle identifier, or a generic one.
struct AppIconView: View {
    let bundleID: String?
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
            .multilineTextAlignment(.center)
    }
}
