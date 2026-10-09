import Foundation

/// Localised string from Localizable.xcstrings (follows the device / per-app language).
func L(_ value: String.LocalizationValue) -> String { String(localized: value) }

/// Anything that can hand out Athom delegation tokens: the iPhone's AuthManager
/// (web session or PAT) and the Apple TV's shared-account store.
@MainActor
protocol TokenProvider: AnyObject {
    func delegationToken(audience: String) async throws -> String
    func invalidateDelegation(_ audience: String)
}
