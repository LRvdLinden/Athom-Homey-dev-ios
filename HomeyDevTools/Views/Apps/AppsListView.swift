import SwiftUI

struct AppsListView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var store

    @State private var source: PortfolioStore.Source = .mine
    @State private var search = ""
    @State private var sort: Sort = .installs

    enum Sort: String, CaseIterable, Identifiable {
        case installs = "Installaties", name = "Naam", rating = "Rating", updated = "Laatst bijgewerkt"
        var id: String { rawValue }
    }

    var body: some View {
        List {
            if store.organizations.isEmpty == false {
                Section {
                    Picker("Bron", selection: $source) {
                        Text("Mijn apps").tag(PortfolioStore.Source.mine)
                        ForEach(store.organizations) { org in
                            Text(org.name).tag(PortfolioStore.Source.org(org.id))
                        }
                    }
                }
            }

            if let err = store.error, source == .mine {
                ErrorBanner(message: err) { Task { await store.load(auth: auth, force: true) } }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            let apps = filtered
            Section {
                ForEach(apps) { app in
                    NavigationLink(value: app) { AppRow(app: app) }
                }
            } header: {
                if !apps.isEmpty {
                    Text("\(apps.count) apps · \(Fmt.number(apps.reduce(0) { $0 + $1.installs })) installaties")
                }
            }

            if case .org(let id) = source, let org = store.organizations.first(where: { $0.id == id }) {
                Section("Organisatie") {
                    LabeledContent("ID", value: org.id)
                    if !org.members.isEmpty { LabeledContent("Leden", value: "\(org.members.count)") }
                    NavigationLink("Ruwe data") { JSONInspectorView(title: org.name, json: org.raw) }
                }
            }
        }
        .overlay {
            if store.isLoading && filtered.isEmpty { ProgressView() }
            else if !store.isLoading && filtered.isEmpty && store.lastLoaded != nil {
                ContentUnavailableView.search(text: search)
            }
        }
        .themedList()
        .navigationTitle("My Apps")
        .navigationDestination(for: DevApp.self) { AppDetailView(app: $0) }
        .searchable(text: $search, prompt: "Zoek op naam of app-id")
        .toolbar {
            AccountSwitcherButton()
            Menu {
                Picker("Sorteer", selection: $sort) { ForEach(Sort.allCases) { Text($0.rawValue).tag($0) } }
            } label: { Image(systemName: "arrow.up.arrow.down") }
        }
        .refreshable { await store.load(auth: auth, force: true) }
        .task { await store.load(auth: auth) }
    }

    private var filtered: [DevApp] {
        var apps = store.apps(for: source)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { apps = apps.filter { $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q) } }
        switch sort {
        case .installs: apps.sort { $0.installs > $1.installs }
        case .name: apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .rating: apps.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .updated: apps.sort { ($0.liveUpdatedAt ?? .distantPast) > ($1.liveUpdatedAt ?? .distantPast) }
        }
        return apps
    }
}
