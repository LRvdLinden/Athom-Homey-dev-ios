import SwiftUI
import Charts

// MARK: - Insights

struct InsightsToolView: View {
    let client: HomeyClient
    @State private var logs: [JSON] = []
    @State private var search = ""
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } }.listRowBackground(Color.clear) }
            ForEach(groups) { group in
                Section(group.id) {
                    ForEach(Array(group.logs.enumerated()), id: \.offset) { _, log in
                        NavigationLink { InsightsLogView(client: client, log: log) } label: {
                            HStack {
                                Image(systemName: log.firstString("type") == "boolean" ? "switch.2" : "chart.xyaxis.line")
                                    .foregroundStyle(Theme.accent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(titleOrID(log))
                                    Text(log.firstString("id")).font(.caption2.monospaced()).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if !log["lastValue"].isNull {
                                    Text("\(log["lastValue"].displayString) \(log["units"].localized)").font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
                .cardRows()
            }
        }
        .themedList()
        .overlay { if loading && logs.isEmpty { ProgressView() } }
        .searchable(text: $search, prompt: "Zoek log")
        .navigationTitle("Insights")
        .refreshable { await load() }
        .task { await load() }
    }

    struct LogGroup: Identifiable { let id: String; let logs: [JSON] }

    private var groups: [LogGroup] {
        let q = search.lowercased()
        let filtered = q.isEmpty ? logs : logs.filter { ($0["title"].localized + $0.firstString("id", "ownerName")).lowercased().contains(q) }
        let dict = Dictionary(grouping: filtered) { $0.firstString("ownerName", "uriObj").isEmpty ? $0.firstString("uri", "ownerUri") : $0.firstString("ownerName") }
        return dict.keys.sorted().map { LogGroup(id: $0, logs: dict[$0] ?? []) }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { logs = try await client.request("/api/manager/insights/log").items; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct InsightsLogView: View {
    let client: HomeyClient
    let log: JSON
    @State private var resolution = "last24Hours"
    struct Point: Identifiable { let id: Date; let value: Double }
    @State private var points: [Point] = []
    @State private var error: String?

    private var minValue: Double { points.map { $0.value }.min() ?? 0 }
    private var maxValue: Double { points.map { $0.value }.max() ?? 0 }
    private func lastValueText(_ v: Double) -> String {
        let units: String = log["units"].localized
        return units.isEmpty ? twoDecimals(v) : twoDecimals(v) + " " + units
    }

    private let resolutions = ["lastHour", "last24Hours", "last7Days", "last31Days", "last1Year"]
    private func label(_ r: String) -> LocalizedStringKey {
        switch r { case "lastHour": "1u"; case "last24Hours": "24u"; case "last7Days": "7d"; case "last31Days": "31d"; default: "1j" }
    }

    var body: some View {
        List {
            Section {
                Picker("Periode", selection: $resolution) {
                    ForEach(resolutions, id: \.self) { Text(label($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                if points.count > 1 {
                    Chart(points) { p in
                        if log.firstString("type") == "boolean" {
                            LineMark(x: .value("Tijd", p.id), y: .value("Waarde", p.value)).interpolationMethod(.stepEnd)
                        } else {
                            AreaMark(x: .value("Tijd", p.id), y: .value("Waarde", p.value))
                                .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("Tijd", p.id), y: .value("Waarde", p.value)).interpolationMethod(.monotone)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                } else if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                } else {
                    Text("Geen waarden in deze periode.").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if let last = points.last {
                    LabeledContent("Laatste waarde", value: lastValueText(last.value))
                    LabeledContent("Minimum", value: twoDecimals(minValue))
                    LabeledContent("Maximum", value: twoDecimals(maxValue))
                }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(titleOrID(log))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: resolution) { await load() }
    }

    private func load() async {
        let uri = log.firstString("uri", "ownerUri")
        let id = log.firstString("id")
        let path = "/api/manager/insights/log/\(uri.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uri)/\(id)/entry?resolution=\(resolution)"
        do {
            let j = try await client.request(path)
            let values = j["values"].isNull ? j.array : j["values"].array
            points = values.compactMap { v in
                guard let t = v["t"].date ?? v["date"].date, let val = v["v"].double ?? v["value"].double else { return nil }
                return Point(id: t, value: val)
            }
            error = nil
        } catch { self.error = error.localizedDescription; points = [] }
    }
}
