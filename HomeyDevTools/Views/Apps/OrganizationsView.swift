import SwiftUI

/// "My Organizations" from Developer Tools: every organisation of the active account,
/// with its apps, members and totals.
struct OrganizationsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        List {
            if let err = store.orgError {
                ErrorBanner(message: err) { Task { await store.load(auth: auth, force: true) } }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            ForEach(store.organizations) { org in
                let apps = store.orgApps[org.id] ?? []
                NavigationLink(value: org) {
                    HStack(spacing: 12) {
                        OrgAvatar(org: org, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(org.name).font(.body.weight(.medium))
                            Text("\(apps.isEmpty ? org.appRefs.count : apps.count) apps · \(org.members.count) leden")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if !apps.isEmpty {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.compact(apps.reduce(0) { $0 + $1.installs })).font(.headline.monospacedDigit())
                                Text("installs").font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .cardRows()
            }
        }
        .themedList()
        .overlay {
            if store.organizations.isEmpty {
                if store.isLoading { ProgressView() }
                else if store.orgError == nil {
                    ContentUnavailableView("Geen organisaties", systemImage: "building.2",
                                           description: Text("Dit account is nog geen lid van een Homey Developer Organization."))
                }
            }
        }
        .navigationTitle("Organisaties")
        .navigationDestination(for: DevOrganization.self) { OrganizationDetailView(org: $0) }
        .navigationDestination(for: DevApp.self) { AppDetailView(app: $0) }
        .toolbar { AccountSwitcherButton() }
        .refreshable { await store.load(auth: auth, force: true) }
        .task { await store.load(auth: auth) }
    }
}

struct OrgAvatar: View {
    let org: DevOrganization
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Theme.accent.opacity(0.15))
            if let url = org.imageURL {
                AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { initials }
            } else { initials }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }

    private var initials: some View {
        Text(org.name.prefix(2).uppercased()).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(Theme.accent)
    }
}

struct OrganizationDetailView: View {
    let org: DevOrganization
    @Environment(PortfolioStore.self) private var store
    @Environment(AuthManager.self) private var auth

    var body: some View {
        let current = store.organizations.first { $0.id == org.id } ?? org
        let apps = store.orgApps[org.id] ?? []
        let totals = PortfolioTotals(apps)

        List {
            Section {
                HStack(spacing: 14) {
                    OrgAvatar(org: current, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(current.name).font(.title3.weight(.semibold))
                        Text(current.id).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                        if !current.descriptionText.isEmpty {
                            Text(current.descriptionText).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)

            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(title: "Installaties", value: Fmt.number(totals.installs), systemImage: "arrow.down.circle")
                    StatTile(title: "Apps", value: "\(apps.count)", systemImage: "square.stack.3d.up")
                    StatTile(title: "Cloud", value: Fmt.number(totals.cloud), systemImage: "cloud", tint: .cyan)
                    StatTile(title: "Local", value: Fmt.number(totals.local), systemImage: "house", tint: .indigo)
                    StatTile(title: "In review", value: "\(totals.inReview)", systemImage: "hourglass", tint: totals.inReview > 0 ? .orange : .secondary)
                    StatTile(title: "Gem. rating", value: totals.avgRating > 0 ? String(format: "%.1f ★", totals.avgRating) : "—", systemImage: "star", tint: .yellow)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section("Apps (\(apps.count))") {
                if apps.isEmpty && store.isLoading { ProgressView() }
                ForEach(apps) { app in NavigationLink(value: app) { AppRow(app: app) } }
            }
            .cardRows()

            if !current.members.isEmpty {
                Section("Leden (\(current.members.count))") {
                    ForEach(Array(current.members.enumerated()), id: \.offset) { _, m in
                        OrgMemberRow(member: m)
                    }
                }
                .cardRows()
            }

            Section {
                if let url = Config.devToolsOrgPage(current.id) {
                    NavigationLink { WebToolsView(start: url) } label: { Label("Openen in Developer Tools", systemImage: "safari") }
                }
                NavigationLink { JSONInspectorView(title: current.name, json: current.raw) } label: { Label("Ruwe API-data", systemImage: "curlybraces") }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load(auth: auth, force: true) }
    }
}

struct OrgMemberRow: View {
    let member: JSON

    var body: some View {
        let u = member["user"].isContainer ? member["user"] : member
        let name: String = {
            let full = "\(u["firstname"].string ?? "") \(u["lastname"].string ?? "")".trimmingCharacters(in: .whitespaces)
            return full.isEmpty ? u.firstString("fullname", "name", "email", "id", "_id") : full
        }()
        let role = member.firstString("role", "roleId")
        let roles = member["roles"].array.compactMap(\.string)
        let avatar = u["avatar"].isContainer ? u["avatar"].firstString("small", "medium", "large", "url") : (u["avatar"].string ?? "")

        HStack(spacing: 12) {
            AsyncImage(url: URL(string: avatar)) { i in i.resizable().scaledToFill() } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if !u.firstString("email").isEmpty && u.firstString("email") != name {
                    Text(u.firstString("email")).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            let r = role.isEmpty ? roles.joined(separator: ", ") : role
            if !r.isEmpty { StateBadge(state: r) }
        }
    }
}
