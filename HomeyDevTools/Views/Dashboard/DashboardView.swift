import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var store

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        let apps = store.allApps
        let totals = PortfolioTotals(apps)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let err = store.error {
                    ErrorBanner(message: err) { Task { await store.load(auth: auth, force: true) } }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    StatTile(title: "Installaties", value: Fmt.number(totals.installs), systemImage: "arrow.down.circle")
                    StatTile(title: "Apps", value: "\(totals.apps)", systemImage: "app.badge")
                    StatTile(title: "Cloud", value: Fmt.number(totals.cloud), systemImage: "cloud", tint: .cyan)
                    StatTile(title: "Local (Pro)", value: Fmt.number(totals.local), systemImage: "house", tint: .indigo)
                    StatTile(title: "In review", value: "\(totals.inReview)", systemImage: "hourglass", tint: totals.inReview > 0 ? .orange : .secondary)
                    StatTile(title: "Gem. rating", value: totals.avgRating > 0 ? String(format: "%.1f ★", totals.avgRating) : "—", systemImage: "star", tint: .yellow)
                }

                if !apps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Installaties per app").font(.headline)
                        InstallsBarChart(apps: Array(apps.prefix(8)))
                    }
                    .padding()
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Top apps").font(.headline).padding([.horizontal, .top])
                        ForEach(apps.prefix(10)) { app in
                            NavigationLink(value: app) {
                                AppRow(app: app).padding(.horizontal).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 72)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    let review = apps.filter(\.inReview)
                    if !review.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Wacht op certificering", systemImage: "hourglass").font(.headline)
                            ForEach(review) { app in
                                HStack {
                                    NavigationLink(value: app) {
                                        HStack { Text(app.name); Spacer(); Text("v\(app.testVersion)").foregroundStyle(.secondary) }
                                    }
                                    .buttonStyle(.plain)
                                    if let bid = app.testBuildId, app.testState == "in_review" {
                                        Button { retractTarget = (app, bid) } label: {
                                            Text("Uit review").font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.orange)
                                    }
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding()
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                } else if store.isLoading {
                    ProgressView("Apps laden…").frame(maxWidth: .infinity).padding(.top, 40)
                } else if store.error == nil {
                    ContentUnavailableView("Nog geen apps", systemImage: "app.dashed", description: Text("Publiceer een app met `homey app publish` om hem hier te zien."))
                }
            }
            .padding()
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Home")
        .toolbar { AccountSwitcherButton() }
        .navigationDestination(for: DevApp.self) { AppDetailView(app: $0) }
        .refreshable { await store.load(auth: auth, force: true) }
        .confirmationDialog("Uit review halen?", isPresented: Binding(get: { retractTarget != nil }, set: { if !$0 { retractTarget = nil } }),
                            titleVisibility: .visible) {
            if let t = retractTarget {
                Button(L("\(t.app.name) v\(t.app.testVersion) uit review halen"), role: .destructive) { Task { await retract(t.app, t.buildId) } }
            }
        } message: {
            Text("De build gaat terug naar Test. Je kunt hem later opnieuw indienen.")
        }
        .actionFeedback($feedback)
        .task { await store.load(auth: auth) }
    }

    @State private var retractTarget: (app: DevApp, buildId: Int)?
    @State private var feedback: String?

    private func retract(_ app: DevApp, _ buildId: Int) async {
        do {
            try await AppsAPI(auth: auth).retractSubmission(app.id, buildId: buildId)
            feedback = L("Uit review gehaald")
            await store.load(auth: auth, force: true)
        } catch { feedback = error.localizedDescription }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AsyncImage(url: auth.avatarURL) { img in img.resizable().scaledToFill() } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44).clipShape(Circle())
            VStack(alignment: .leading) {
                Text(auth.displayName.isEmpty ? L("Welkom") : L("Hoi \(auth.user["firstname"].string ?? auth.displayName)"))
                    .font(.title3.weight(.semibold))
                if let last = store.lastLoaded {
                    Text("Bijgewerkt \(Fmt.relative(last))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.isLoading { ProgressView() }
        }
    }
}

struct AppRow: View {
    let app: DevApp

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(url: app.iconURL, brand: app.brandColor, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.name).font(.body.weight(.medium)).lineLimit(1)
                    if app.inReview { StateBadge(state: "in_review") }
                }
                Text(app.id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    if !app.liveVersion.isEmpty { Text("live \(app.liveVersion)").foregroundStyle(.green) }
                    if !app.testVersion.isEmpty && app.testVersion != app.liveVersion { Text("test \(app.testVersion)").foregroundStyle(.blue) }
                    if let r = app.rating, r > 0 { Text("★ \(Fmt.rating(r))").foregroundStyle(.yellow) }
                }
                .font(.caption2.weight(.medium))
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.compact(app.installs)).font(.headline.monospacedDigit())
                Text("installs").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}


/// Horizontal stacked bars (Cloud + Local) with the app name and total on their
/// own line above each bar, so labels never overlap the bars.
struct InstallsBarChart: View {
    let apps: [DevApp]
    private let cloud = Color.cyan
    private let local = Color.indigo

    var body: some View {
        let maxValue = max(apps.map { $0.installsCloud + $0.installsLocal }.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(apps) { app in
                NavigationLink(value: app) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(app.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Fmt.number(app.installsCloud + app.installsLocal))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        GeometryReader { geo in
                            let w = geo.size.width
                            let cw = w * CGFloat(app.installsCloud) / CGFloat(maxValue)
                            let lw = w * CGFloat(app.installsLocal) / CGFloat(maxValue)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.07))
                                HStack(spacing: 2) {
                                    if app.installsCloud > 0 {
                                        Rectangle().fill(cloud).frame(width: max(cw, 3))
                                    }
                                    if app.installsLocal > 0 {
                                        Rectangle().fill(local).frame(width: max(lw, 3))
                                    }
                                }
                                .clipShape(Capsule())
                            }
                        }
                        .frame(height: 10)
                        HStack(spacing: 12) {
                            Text("Cloud \(Fmt.number(app.installsCloud))")
                            Text("Local \(Fmt.number(app.installsLocal))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 16) {
                legend(cloud, "Cloud")
                legend(local, "Local")
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 2)
        }
    }

    private func legend(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title)
        }
    }
}
