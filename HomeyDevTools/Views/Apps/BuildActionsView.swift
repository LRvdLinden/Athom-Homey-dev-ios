import SwiftUI

/// Build actions exactly as on the Developer Tools build page:
/// draft → Publish to Test · test → Submit for Certification ·
/// in_review → Retract Submission · reviewed_approved → Publish to Live.
struct BuildActionsSection: View {
    let appId: String
    let buildId: Int
    let version: String
    let state: String
    var onChanged: () async -> Void = {}

    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var store

    @State private var busy = false
    @State private var autoRelease = true
    @State private var confirm: Action?
    @State private var message: String?
    @State private var error: String?

    enum Action: Identifiable {
        case publishTest, submit, retract, publishLive
        var id: Int { hashValue }
    }

    var body: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                StateBadge(state: state)
            }
            switch state {
            case "draft":
                actionButton("Publiceer naar Test", icon: "flask", tint: .blue) { confirm = .publishTest }
            case "test":
                Toggle("Automatisch live na goedkeuring", isOn: $autoRelease)
                actionButton("Indienen voor certificering", icon: "checkmark.seal", tint: Theme.accent) { confirm = .submit }
            case "in_review":
                actionButton("Uit review halen", icon: "arrow.uturn.backward.circle", tint: .orange) { confirm = .retract }
            case "reviewed_approved":
                actionButton("Publiceer naar Live", icon: "paperplane.circle", tint: .green) { confirm = .publishLive }
            case "reviewed_rejected":
                Label("Afgewezen – bekijk de opmerkingen hieronder, pas aan en dien een nieuwe build in.", systemImage: "xmark.octagon")
                    .font(.footnote).foregroundStyle(.red)
            case "live":
                Label("Deze build is live in de Homey App Store.", systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.green)
            default:
                Text("Geen acties beschikbaar voor deze status.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            if let message { Label(message, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.green) }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Acties · v\(version)")
        }
        .cardRows()
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { action in
            Button(confirmButton(action), role: action == .retract ? .destructive : nil) { Task { await run(action) } }
        } message: { action in
            Text(confirmMessage(action))
        }
    }

    private func actionButton(_ title: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon).font(.body.weight(.semibold))
                Spacer()
                if busy { ProgressView() }
            }
        }
        .tint(tint)
        .foregroundStyle(tint)
        .disabled(busy)
    }

    private var confirmTitle: String {
        switch confirm {
        case .publishTest: L("v\(version) publiceren naar Test?")
        case .submit: L("v\(version) indienen voor certificering?")
        case .retract: L("v\(version) uit review halen?")
        case .publishLive: L("v\(version) publiceren naar Live?")
        case nil: ""
        }
    }

    private func confirmButton(_ a: Action) -> String {
        switch a {
        case .publishTest: L("Publiceer naar Test")
        case .submit: L("Indienen")
        case .retract: L("Uit review halen")
        case .publishLive: L("Publiceer naar Live")
        }
    }

    private func confirmMessage(_ a: Action) -> String {
        switch a {
        case .publishTest: L("Testers kunnen deze versie daarna installeren via de testlink.")
        case .submit: autoRelease ? L("Athom beoordeelt de build en zet hem na goedkeuring automatisch live.")
                                  : L("Athom beoordeelt de build. Na goedkeuring zet je hem zelf live.")
        case .retract: L("De build gaat terug naar Test. Je kunt hem later opnieuw indienen.")
        case .publishLive: L("Alle gebruikers krijgen deze versie via de Homey App Store.")
        }
    }

    private func run(_ a: Action) async {
        busy = true; error = nil; message = nil
        defer { busy = false }
        let api = AppsAPI(auth: auth)
        do {
            switch a {
            case .publishTest: try await api.setBuildChannel(appId, buildId: buildId, channel: "test"); message = L("Gepubliceerd naar Test")
            case .submit: try await api.submitForCertification(appId, buildId: buildId, autoRelease: autoRelease); message = L("Ingediend voor certificering")
            case .retract: try await api.retractSubmission(appId, buildId: buildId); message = L("Uit review gehaald")
            case .publishLive: try await api.setBuildChannel(appId, buildId: buildId, channel: "live"); message = L("Gepubliceerd naar Live")
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await onChanged()
            await store.load(auth: auth, force: true)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.error = error.localizedDescription
        }
    }
}

/// Conversation with the Athom reviewer for a submitted build.
struct SubmissionCommentsSection: View {
    let appId: String
    let buildId: Int
    @Environment(AuthManager.self) private var auth
    @State private var comments: [JSON] = []
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        Section {
            if comments.isEmpty {
                Text("Nog geen opmerkingen.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(comments.enumerated()), id: \.offset) { _, c in
                let author = c["user"].isContainer ? c["user"].firstString("firstname", "fullname", "name", "email") : c.firstString("author", "userName", "from")
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(author.isEmpty ? "Athom" : author).font(.caption.weight(.semibold))
                        Spacer()
                        Text(Fmt.relative(c["createdAt"].date)).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Text(c.firstString("text", "message", "comment")).font(.callout).textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
            HStack(alignment: .bottom) {
                TextField("Stel een vraag of reageer…", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                Button {
                    Task { await send() }
                } label: {
                    if sending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Review-opmerkingen")
        }
        .cardRows()
        .task { await load() }
    }

    private func load() async {
        comments = (try? await AppsAPI(auth: auth).submissionComments(appId, buildId: buildId)) ?? []
    }

    private func send() async {
        sending = true; error = nil
        defer { sending = false }
        do {
            try await AppsAPI(auth: auth).addSubmissionComment(appId, buildId: buildId, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            text = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

/// Build detail with info, actions, reviewer comments and crashes.
struct BuildDetailView: View {
    let appId: String
    let build: DevBuild
    @Environment(AuthManager.self) private var auth
    @State private var current: DevBuild?
    @State private var crashes: [DevCrash] = []

    var body: some View {
        let b = current ?? build
        List {
            BuildActionsSection(appId: appId, buildId: b.id, version: b.version, state: b.state) { await reload() }

            Section {
                LabeledContent("Versie", value: b.version)
                LabeledContent("Build", value: "#\(b.id)")
                LabeledContent("Aangemaakt", value: Fmt.date(b.createdAt))
                LabeledContent("Status gewijzigd", value: Fmt.date(b.stateChangedAt))
                LabeledContent("Installaties", value: Fmt.number(b.installs))
                LabeledContent("Crashes", value: Fmt.number(b.crashes))
                if !b.platforms.isEmpty { LabeledContent("Platforms", value: b.platforms.joined(separator: ", ")) }
                if !b.sdk.isEmpty { LabeledContent("Compatibiliteit", value: b.sdk) }
            }
            .cardRows()

            if !b.changelog.isEmpty { Section("Changelog") { Text(b.changelog) }.cardRows() }

            if ["test", "in_review", "reviewed_approved", "reviewed_rejected", "live"].contains(b.state) {
                SubmissionCommentsSection(appId: appId, buildId: b.id)
            }

            Section("Crashes (\(crashes.count))") {
                if crashes.isEmpty { Text("Geen crashes 🎉").foregroundStyle(.secondary) }
                ForEach(crashes) { c in NavigationLink { CrashDetailView(crash: c) } label: { CrashRow(crash: c) } }
            }
            .cardRows()

            Section {
                NavigationLink { JSONInspectorView(title: "Build #\(b.id)", json: b.raw) } label: { Label("Ruwe API-data", systemImage: "curlybraces") }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("v\(build.version)")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        let api = AppsAPI(auth: auth)
        if let fresh = try? await api.build(appId, build.id) { current = fresh }
        crashes = (try? await api.crashes(appId, buildId: build.id)) ?? crashes
    }
}

// MARK: - App-level actions

/// User reviews (ratings) with developer responses.
struct ReviewsView: View {
    let appId: String
    @Environment(AuthManager.self) private var auth
    @State private var reviews: [JSON] = []
    @State private var loading = true
    @State private var responding: JSON?
    @State private var responseText = ""
    @State private var feedback: String?

    var body: some View {
        List {
            ForEach(Array(reviews.enumerated()), id: \.offset) { _, r in
                ReviewRow(review: r)
                    .swipeActions {
                        Button("Reageer") { responseText = r.firstString("response"); responding = r }.tint(Theme.accent)
                        if !r.firstString("response").isEmpty {
                            Button("Verwijder reactie", role: .destructive) { Task { await deleteResponse(r) } }
                        }
                    }
                    .contextMenu {
                        Button { responseText = r.firstString("response"); responding = r } label: { Label("Reageer", systemImage: "arrowshape.turn.up.left") }
                    }
                    .cardRows()
            }
        }
        .themedList()
        .overlay {
            if reviews.isEmpty {
                if loading { ProgressView() } else { ContentUnavailableView("Nog geen reviews", systemImage: "star") }
            }
        }
        .navigationTitle("Reviews")
        .refreshable { await load() }
        .task { await load() }
        .alert("Reactie op review", isPresented: Binding(get: { responding != nil }, set: { if !$0 { responding = nil } })) {
            TextField("Je reactie", text: $responseText, axis: .vertical)
            Button("Annuleer", role: .cancel) { responding = nil }
            Button("Plaats") { if let r = responding { Task { await respond(r) } }; responding = nil }
        }
        .actionFeedback($feedback)
    }

    private func reviewUserId(_ r: JSON) -> String { r.firstString("userId", "user_id").isEmpty ? r["user"].firstString("_id", "id") : r.firstString("userId", "user_id") }

    private func load() async {
        loading = true; defer { loading = false }
        reviews = (try? await AppsAPI(auth: auth).reviews(appId)) ?? reviews
    }

    private func respond(_ r: JSON) async {
        do {
            try await AppsAPI(auth: auth).respondToReview(appId, userId: reviewUserId(r), response: responseText)
            feedback = L("Reactie geplaatst"); await load()
        } catch { feedback = error.localizedDescription }
    }

    private func deleteResponse(_ r: JSON) async {
        do {
            try await AppsAPI(auth: auth).deleteReviewResponse(appId, userId: reviewUserId(r))
            feedback = L("Reactie verwijderd"); await load()
        } catch { feedback = error.localizedDescription }
    }
}

struct ReviewRow: View {
    let review: JSON
    var body: some View {
        let rating = review["rating"].int ?? 0
        let name = review["user"].isContainer ? review["user"].firstString("firstname", "fullname", "name") : review.firstString("userName", "name")
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 1) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: i < rating ? "star.fill" : "star").font(.caption).foregroundStyle(.yellow)
                    }
                }
                if !name.isEmpty { Text(name).font(.caption.weight(.semibold)) }
                Spacer()
                Text(review.firstString("version")).font(.caption2.monospaced()).foregroundStyle(Theme.textSecondary)
            }
            if !review.firstString("comment").isEmpty { Text(review.firstString("comment")).font(.callout) }
            if !review.firstString("response").isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.caption2).foregroundStyle(Theme.accent)
                    Text(review.firstString("response")).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                .padding(8)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            Text(Fmt.relative(review["createdAt"].date ?? review["updatedAt"].date)).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

/// E-mail notification settings for an app (Developer Tools → App → Settings).
struct AppNotificationSettingsView: View {
    let appId: String
    @Environment(AuthManager.self) private var auth
    @State private var crash = false
    @State private var suggestion = false
    @State private var thanks = false
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("E-mail bij crashes", isOn: $crash)
                Toggle("E-mail bij suggesties", isOn: $suggestion)
                Toggle("E-mail bij bedankjes", isOn: $thanks)
            } footer: {
                Text("Wordt direct opgeslagen in je Homey Developer-account.")
            }
            .cardRows()
            .disabled(!loaded)
            if let error { Section { Text(error).foregroundStyle(.red) }.cardRows() }
        }
        .themedList()
        .navigationTitle("Meldingen")
        .task {
            if let s = try? await AppsAPI(auth: auth).appSettings(appId) {
                crash = s["sendEmailCrash"].bool ?? false
                suggestion = s["sendEmailSuggestion"].bool ?? false
                thanks = s["sendEmailThanks"].bool ?? false
            }
            loaded = true
        }
        .onChange(of: crash) { _, _ in save() }
        .onChange(of: suggestion) { _, _ in save() }
        .onChange(of: thanks) { _, _ in save() }
    }

    private func save() {
        guard loaded else { return }
        Task {
            do { try await AppsAPI(auth: auth).updateAppSettings(appId, crash: crash, suggestion: suggestion, thanks: thanks); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// Transfer an app to one of your organisations.
struct TransferAppView: View {
    let app: DevApp
    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var target: DevOrganization?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        List {
            Section {
                ForEach(store.organizations) { org in
                    Button { target = org } label: {
                        HStack(spacing: 10) {
                            OrgAvatar(org: org, size: 32)
                            Text(org.name).foregroundStyle(.primary)
                            Spacer()
                            if busy && target?.id == org.id { ProgressView() }
                        }
                    }
                }
            } footer: {
                Text("De app wordt eigendom van de organisatie. Leden met de juiste rol kunnen hem daarna beheren.")
            }
            .cardRows()
            if let error { Section { Text(error).foregroundStyle(.red) }.cardRows() }
        }
        .themedList()
        .overlay { if store.organizations.isEmpty { ContentUnavailableView("Geen organisaties", systemImage: "building.2") } }
        .navigationTitle("Overdragen")
        .confirmationDialog("Overdragen?", isPresented: Binding(get: { target != nil && !busy }, set: { if !$0 && !busy { target = nil } }),
                            titleVisibility: .visible, presenting: target) { org in
            Button(L("\(app.name) overdragen aan \(org.name)"), role: .destructive) { Task { await transfer(org) } }
        }
    }

    private func transfer(_ org: DevOrganization) async {
        busy = true; defer { busy = false; target = nil }
        do {
            try await AppsAPI(auth: auth).transferToOrganization(app.id, orgId: org.id)
            await store.load(auth: auth, force: true)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
