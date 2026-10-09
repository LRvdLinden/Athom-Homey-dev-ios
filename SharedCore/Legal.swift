import Foundation

/// Version, build and copyright shown at the bottom of the Account page.
enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–" }
    static var versionLine: String { L("Versie: \(version) (\(build))") }
    static let copyright = "© HomeyDev - PixelForges"
}

/// Disclaimer and privacy texts, shared by the iPhone/iPad and Apple TV apps.
struct LegalDocument: Identifiable {
    struct Part: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let text: String
    }

    let id: String
    let title: String
    let icon: String
    let intro: String
    let parts: [Part]
    let updated: String

    static var all: [LegalDocument] { [privacy, disclaimer] }

    static var privacy: LegalDocument {
        LegalDocument(
            id: "privacy",
            title: L("Privacy & voorwaarden"),
            icon: "lock.shield.fill",
            intro: L("HomeyDev is gemaakt om je eigen ontwikkelaarsgegevens bij Homey te bekijken en te beheren. We verzamelen zo min mogelijk, en wat de app bewaart blijft op je eigen toestellen."),
            parts: [
                Part(icon: "person.badge.key.fill", title: L("Je account"),
                     text: L("Je logt in bij Athom (Homey) via hun eigen inlogpagina. De app krijgt daarbij een sessie of een Personal Access Token. Die wordt alleen in de iOS-sleutelhanger op je toestel bewaard en nooit naar ons gestuurd.")),
                Part(icon: "arrow.left.arrow.right", title: L("Met wie de app praat"),
                     text: L("De app haalt gegevens rechtstreeks op bij Athom: api.athom.com, apps-api.athom.com, tools.developer.homey.app en je eigen Homey's. Er zit geen eigen server van ons tussen.")),
                Part(icon: "chart.bar.xaxis", title: L("Geen tracking"),
                     text: L("De app bevat geen advertenties, analytics of tracking. We zien niet welke apps, Homey's of gegevens je bekijkt.")),
                Part(icon: "bell.badge.fill", title: L("Meldingen"),
                     text: L("Statusmeldingen op je toestel worden door de app zelf gemaakt. Zet je ‘Direct via push’ aan, dan registreert de app je toestel bij OneSignal, met je Athom-gebruikers-ID en je meldingsvoorkeuren als kenmerken. De statuscontrole voor push draait in de GitHub-omgeving van de ontwikkelaar. Zet push uit om je toestel af te melden.")),
                Part(icon: "appletv.fill", title: L("Apple TV en widgets"),
                     text: L("Koppelen met je Apple TV gaat versleuteld via je eigen netwerk of via je iCloud-sleutelhanger. Widgets lezen een samenvatting die de app op je toestel opslaat.")),
                Part(icon: "trash.fill", title: L("Verwijderen"),
                     text: L("Meld je af onder Account of verwijder de app, dan zijn alle opgeslagen sessies en tokens weg. Je Personal Access Tokens trek je in via Developer Tools → My Account.")),
                Part(icon: "doc.text.fill", title: L("Voorwaarden"),
                     text: L("Je gebruikt de app op eigen risico en volgens de voorwaarden van Athom voor Homey en Developer Tools. Gebruik de app niet om toegang te krijgen tot accounts of gegevens die niet van jou zijn.")),
            ],
            updated: L("Bijgewerkt: oktober 2026")
        )
    }

    static var disclaimer: LegalDocument {
        LegalDocument(
            id: "disclaimer",
            title: L("Disclaimer"),
            icon: "hand.raised.fill",
            intro: L("HomeyDev is een onofficiële app, gemaakt door PixelForges voor Homey-ontwikkelaars."),
            parts: [
                Part(icon: "building.2.fill", title: L("Niet van Athom"),
                     text: L("Deze app is niet gemaakt, goedgekeurd of ondersteund door Athom B.V. Homey en het Homey-logo zijn handelsmerken van Athom B.V.")),
                Part(icon: "exclamationmark.triangle.fill", title: L("Acties zijn echt"),
                     text: L("Builds publiceren, indienen of terugtrekken, reviews beantwoorden, leden beheren en Homey-acties zoals herstarten of Z-Wave-nodes verwijderen gebeuren echt in je account. Controleer wat je doet; de ontwikkelaar is niet aansprakelijk voor de gevolgen.")),
                Part(icon: "clock.arrow.circlepath", title: L("Gegevens"),
                     text: L("Cijfers en statussen komen van Athom en kunnen vertraagd of onvolledig zijn. Meldingen kunnen later of niet aankomen.")),
                Part(icon: "wrench.and.screwdriver.fill", title: L("Zonder garantie"),
                     text: L("De app wordt geleverd zoals hij is, zonder garantie. Functies kunnen stoppen met werken als Athom iets verandert.")),
                Part(icon: "envelope.fill", title: L("Contact"),
                     text: L("Vragen of een fout gevonden? Open een issue op GitHub: github.com/LRvdLinden/Athom-Homey-dev-ios.")),
            ],
            updated: L("Bijgewerkt: oktober 2026")
        )
    }
}
