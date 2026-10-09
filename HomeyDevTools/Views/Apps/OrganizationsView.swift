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

            OrgMembersSection(org: current)

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
        .toolbar {
            if current.canManageMembers {
                Menu {
                    Button { showInvite = true } label: { Label("Lid uitnodigen", systemImage: "person.badge.plus") }
                    if current.canChangeRoles {
                        Button { newName = current.name; showRename = true } label: { Label("Organisatie hernoemen", systemImage: "pencil") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showInvite) { InviteMemberSheet(org: current) }
        .alert("Organisatie hernoemen", isPresented: $showRename) {
            TextField("Naam", text: $newName)
            Button("Annuleer", role: .cancel) {}
            Button("Bewaar") { Task { await rename(current) } }
        }
        .actionFeedback($feedback)
    }

    @State private var showInvite = false
    @State private var showRename = false
    @State private var newName = ""
    @State private var feedback: String?

    private func rename(_ org: DevOrganization) async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await AppsAPI(auth: auth).renameOrganization(orgId: org.id, name: name)
            feedback = L("Organisatie hernoemd")
            await store.load(auth: auth, force: true)
        } catch { feedback = error.localizedDescription }
    }
}

/// Members with profile pictures; owners/admins can change roles and remove members.
struct OrgMembersSection: View {
    let org: DevOrganization
    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var store
    @State private var removing: OrgMember?
    @State private var feedback: String?

    var body: some View {
        let members = org.members.enumerated().map { OrgMember($1, index: $0) }
        Section {
            ForEach(members) { m in
                OrgMemberRow(member: m)
                    .contextMenu { menu(m) }
                    .swipeActions {
                        if org.canManageMembers && m.role != "owner" {
                            Button("Verwijderen", role: .destructive) { removing = m }
                        }
                    }
            }
        } header: {
            Text("Leden (\(members.count))")
        } footer: {
            if org.canManageMembers { Text("Houd een lid ingedrukt om de rol te wijzigen, veeg om te verwijderen.") }
        }
        .cardRows()
        .confirmationDialog("Lid verwijderen?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { m in
            Button(L("\(m.name) verwijderen uit \(org.name)"), role: .destructive) { Task { await remove(m) } }
        }
        .actionFeedback($feedback)
    }

    @ViewBuilder
    private func menu(_ m: OrgMember) -> some View {
        if org.canChangeRoles && m.role != "owner" {
            Picker("Rol", selection: Binding(get: { m.role }, set: { r in Task { await setRole(m, r) } })) {
                ForEach(AppsAPI.organizationRoles, id: \.self) { r in Text(roleLabel(r)).tag(r) }
            }
        }
        if !m.email.isEmpty {
            Button { UIPasteboard.general.string = m.email } label: { Label("Kopieer e-mail", systemImage: "envelope") }
        }
        if !m.userId.isEmpty {
            Button { UIPasteboard.general.string = m.userId } label: { Label("Kopieer gebruikers-ID", systemImage: "number") }
        }
    }

    private func setRole(_ m: OrgMember, _ role: String) async {
        guard role != m.role else { return }
        do {
            try await AppsAPI(auth: auth).updateMemberRole(orgId: org.id, memberId: m.id, role: role)
            feedback = L("Rol bijgewerkt")
            await store.load(auth: auth, force: true)
        } catch { feedback = error.localizedDescription }
    }

    private func remove(_ m: OrgMember) async {
        do {
            try await AppsAPI(auth: auth).removeMember(orgId: org.id, memberId: m.id)
            feedback = L("Lid verwijderd")
            await store.load(auth: auth, force: true)
        } catch { feedback = error.localizedDescription }
    }
}

func roleLabel(_ role: String) -> String {
    switch role {
    case "owner": L("Owner")
    case "admin": L("Admin")
    case "developer": L("Developer")
    case "support": L("Support")
    default: role.capitalized
    }
}

struct InviteMemberSheet: View {
    let org: DevOrganization
    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role = "developer"
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-mailadres", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Rol", selection: $role) {
                        ForEach(AppsAPI.organizationRoles, id: \.self) { r in Text(roleLabel(r)).tag(r) }
                    }
                } footer: {
                    Text("De uitnodiging wordt per e-mail verstuurd naar een bestaand Homey-account.")
                }
                .cardRows()
                if let error { Section { Text(error).foregroundStyle(.red) }.cardRows() }
            }
            .themedList()
            .navigationTitle(org.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Uitnodigen") { Task { await invite() } }
                            .disabled(!email.contains("@"))
                    }
                }
            }
        }
    }

    private func invite() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await AppsAPI(auth: auth).inviteMember(orgId: org.id, email: email.trimmingCharacters(in: .whitespaces), role: role)
            await store.load(auth: auth, force: true)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct OrgMemberRow: View {
    let member: OrgMember

    var body: some View {
        HStack(spacing: 12) {
            AccountAvatar(url: member.avatarURL, initials: member.initials, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).lineLimit(1)
                if !member.email.isEmpty && member.email != member.name {
                    Text(member.email).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            Spacer()
            if !member.role.isEmpty {
                Text(roleLabel(member.role))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(roleColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(roleColor)
            }
        }
        .padding(.vertical, 2)
    }

    private var roleColor: Color {
        switch member.role {
        case "owner": .orange
        case "admin": Theme.accent
        case "developer": .green
        default: .secondary
        }
    }
}
