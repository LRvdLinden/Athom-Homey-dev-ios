import Foundation
import MultipeerConnectivity
import Observation

/// iPhone/iPad/Mac side of the local-network pairing: finds Apple TVs running
/// the app, sends the code shown on the TV and then the accounts.
@MainActor
@Observable
final class TVLinkSender: NSObject {
    struct FoundTV: Identifiable, Hashable {
        let peer: MCPeerID
        var id: MCPeerID { peer }
        var name: String { peer.displayName }
    }

    enum Status: Equatable {
        case searching
        case sending
        case done(Int)
        case failed(String)
    }

    private(set) var found: [FoundTV] = []
    private(set) var status: Status = .searching

    @ObservationIgnored private let peer = MCPeerID(displayName: "iPhone")
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var pendingPayload: Data?
    @ObservationIgnored private var timeout: Task<Void, Never>?

    func start() {
        guard browser == nil else { return }
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: TVLink.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        status = .searching
    }

    func stop() {
        timeout?.cancel()
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        found = []
    }

    /// Invites the Apple TV with the code it shows and sends the accounts once connected.
    func send(_ accounts: [SharedAccount], to tv: FoundTV, code: String) {
        guard let browser, let payload = TVLink.encode(TVLink.Payload(accounts: accounts)) else { return }
        session?.disconnect()
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        pendingPayload = payload
        status = .sending
        browser.invitePeer(tv.peer, to: session, withContext: Data(code.utf8), timeout: 20)
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, self.status == .sending else { return }
            self.fail(L("Geen antwoord van de Apple TV. Controleer de code en of beide op hetzelfde netwerk zitten."))
        }
    }

    func reset() { status = .searching }

    private func fail(_ message: String) {
        timeout?.cancel()
        session?.disconnect()
        status = .failed(message)
    }

    // MARK: Main-actor handlers

    private func handle(state: MCSessionState, peerID: MCPeerID) {
        switch state {
        case .connected:
            guard let data = pendingPayload, let session else { return }
            do {
                try session.send(data, toPeers: [peerID], with: .reliable)
            } catch {
                fail(error.localizedDescription)
            }
        case .notConnected:
            if status == .sending { fail(L("De Apple TV weigerde de verbinding. Klopt de code?")) }
        default:
            break
        }
    }

    private func handle(reply data: Data) {
        timeout?.cancel()
        pendingPayload = nil
        if let reply = TVLink.decode(TVLink.Reply.self, from: data), reply.ok {
            status = .done(reply.count)
        } else {
            status = .failed(L("De Apple TV kon de accounts niet opslaan."))
        }
        session?.disconnect()
    }
}

// Multipeer calls its delegates on background queues; hop to the main actor.
extension TVLinkSender: MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !self.found.contains(where: { $0.peer == peerID }) { self.found.append(FoundTV(peer: peerID)) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.found.removeAll { $0.peer == peerID } }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.status = .failed(message) }
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.handle(state: state, peerID: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.handle(reply: data) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
