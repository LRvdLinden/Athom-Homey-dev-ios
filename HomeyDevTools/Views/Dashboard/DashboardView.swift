import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var store

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

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
                        Chart(apps.prefix(8)) { app in
                            BarMark(x: .value("Installaties", app.installsCloud), y: .value("App", app.name))
                                .foregroundStyle(by: .value("Type", "Cloud"))
                            BarMark(x: .value("Installaties", app.installsLocal), y: .value("App", app.name))
                                .foregroundStyle(by: .value("Type", "Local"))
                        }
                        .chartForegroundStyleScale(["Cloud": Color.cyan, "Local": Color.indigo])
                        .frame(height: CGFloat(min(apps.count, 8)) * 34 + 40)
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
                                HStack { Text(app.name); Spacer(); Text("v\(app.testVersion)").foregroundStyle(.secondary) }
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
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Home")
        .toolbar { AccountSwitcherButton() }
        .navigationDestination(for: DevApp.self) { AppDetailView(app: $0) }
        .refreshable { await store.load(auth: auth, force: true) }
        .task { await store.load(auth: auth) }
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
