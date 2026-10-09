import SwiftUI

struct AccountAvatar: View {
    let url: URL?
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(Theme.buttonGradient)
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Toolbar avatar of the active account; tap to switch (like Facebook / Instagram).
struct AccountSwitcherButton: View {
    @Environment(AuthManager.self) private var auth
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            AccountAvatar(url: auth.avatarURL, initials: auth.active?.initials ?? "", size: 30)
                .overlay(alignment: .bottomTrailing) {
                    if auth.accounts.count > 1 {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white, Theme.accent)
                            .offset(x: 3, y: 3)
                    }
                }
        }
        .accessibilityLabel("Wissel van account")
        .sheet(isPresented: $show) {
            AccountSwitcherSheet().presentationDetents([.medium, .large])
        }
    }
}

struct AccountSwitcherSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var addAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(auth.accounts.sorted { $0.lastUsed > $1.lastUsed }) { acc in
                        Button {
                            auth.switchTo(acc.id)
                            dismiss()
                        } label: {
                            AccountRow(account: acc, isActive: acc.id == auth.activeID)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Afmelden", role: .destructive) { auth.signOut(acc.id) }
                        }
                    }
                }
                .cardRows()

                Section {
                    Button { addAccount = true } label: {
                        Label("Account toevoegen", systemImage: "plus.circle.fill")
                    }
                }
                .cardRows()
            }
            .themedList()
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .fullScreenCover(isPresented: $addAccount) { LoginView(isAddingAccount: true) }
        }
    }
}

struct AccountRow: View {
    let account: StoredAccount
    var isActive = false

    var body: some View {
        HStack(spacing: 12) {
            AccountAvatar(url: account.avatarURL, initials: account.initials, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name.isEmpty ? account.email : account.name).font(.body.weight(.medium))
                Text(account.email).font(.caption).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 4) {
                    Image(systemName: account.credential.isWeb ? "person.badge.key" : "key")
                    Text(account.methodLabel)
                    if account.needsLogin { Text("· opnieuw inloggen").foregroundStyle(.orange) }
                }
                .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.accent)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

extension Credential {
    var isWeb: Bool { if case .web = self { return true }; return false }
}
