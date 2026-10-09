import Foundation
import MultipeerConnectivity

/// Pairing between the iPhone/iPad/Mac app and the Apple TV over the local network
/// (Multipeer Connectivity, encrypted). The Apple TV shows a 4-digit code; the iPhone
/// finds the Apple TV, sends that code with its invitation, and after the TV accepts
/// it sends the accounts (with their Personal Access Tokens). No iCloud needed.
enum TVLink {
    /// Bonjour service type: `_homeydev-tv._tcp` / `_homeydev-tv._udp` (also in Info.plist).
    static let serviceType = "homeydev-tv"

    struct Payload: Codable {
        var accounts: [SharedAccount]
    }

    struct Reply: Codable {
        var ok: Bool
        var count: Int
    }

    static func encode<T: Encodable>(_ value: T) -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        return try? e.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(type, from: data)
    }

    static func newCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }
}

/// Carries a non-Sendable value (an Objective-C completion handler) across to the main actor.
struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
