import Foundation
import MultipeerConnectivity
import Observation

/// Apple TV side of the local-network pairing. Advertises itself, shows a 4-digit
/// code and only accepts an iPhone that sends that code with its invitation.
@MainActor
@Observable
final class TVLinkReceiver: NSObject {
    enum Status: Equatable {
        case idle
        case waiting
        case connecting
        case received(Int)
        case failed(String)
    }

    private(set) var code = TVLink.newCode()
    private(set) var status: Status = .idle

    /// Called with the accounts the iPhone sent.
    @ObservationIgnored var onAccounts: ([SharedAccount]) -> Void = { _ in }

    @ObservationIgnored private let peer = MCPeerID(displayName: "Apple TV")
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var wrongCodes = 0

    func start() {
        guard advertiser == nil else { return }
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["app": "homeydev"], serviceType: TVLink.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        status = .waiting
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        session = nil
        status = .idle
    }

    /// New code, e.g. after a successful pairing or too many wrong attempts.
    func renewCode() {
        code = TVLink.newCode()
        wrongCodes = 0
    }

    // MARK: Main-actor handlers

    private func handleInvitation(code sent: String, accept: @escaping (Bool, MCSession?) -> Void) {
        guard let session else { accept(false, nil); return }
        if sent == code {
            status = .connecting
            accept(true, session)
        } else {
            wrongCodes += 1
            if wrongCodes >= 3 { renewCode() }
            status = .failed(L("Verkeerde code ingevoerd op de iPhone."))
            accept(false, nil)
        }
    }

    private func handle(data: Data, from peerID: MCPeerID) {
        guard let payload = TVLink.decode(TVLink.Payload.self, from: data) else {
            status = .failed(L("Onbekende gegevens ontvangen."))
            return
        }
        let accounts = payload.accounts.filter { !$0.pat.isEmpty }
        if let reply = TVLink.encode(TVLink.Reply(ok: !accounts.isEmpty, count: accounts.count)) {
            try? session?.send(reply, toPeers: [peerID], with: .reliable)
        }
        status = accounts.isEmpty ? .failed(L("Er zaten geen bruikbare accounts in.")) : .received(accounts.count)
        renewCode()
        // Save after the reply had time to reach the iPhone: saving switches the
        // screen, which stops this receiver.
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            self.onAccounts(accounts)
        }
    }

    private func handle(state: MCSessionState) {
        switch state {
        case .connected: status = .connecting
        case .notConnected:
            if case .connecting = status { status = .waiting }
        default: break
        }
    }
}

// Multipeer calls its delegates on background queues; hop to the main actor.
extension TVLinkReceiver: MCNearbyServiceAdvertiserDelegate, MCSessionDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let sent = context.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let handler = UncheckedBox(invitationHandler)
        Task { @MainActor in
            self.handleInvitation(code: sent) { accept, session in handler.value(accept, session) }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.status = .failed(message) }
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.handle(state: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.handle(data: data, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
