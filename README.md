<p align="center"><img src="HomeyDevTools/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="160" alt="App icon"></p>

# Developer Tools voor Homey – iOS

Native SwiftUI-app (iOS/iPadOS 17+) met de functies van [tools.developer.homey.app](https://tools.developer.homey.app). Je kunt meerdere accounts gebruiken en de app ondersteunt licht en donker.

> Onofficiële app. Homey en het Homey-logo zijn van Athom B.V.

## Functies

| Tab | Wat |
|---|---|
| **Home** | Totalen over al je apps en organisaties: installaties, Cloud/Local, in review en gemiddelde rating. Verder een grafiek per app, je topapps en apps die op certificering wachten. |
| **My Apps** | Je eigen apps, met zoeken en sorteren. Per app: statistieken, installatietrend (7d/30d/90d/1j/alles), de live build met changelog en permissies, alle builds, crashes met stacktrace, suggesties, apparaten per driver en de ruwe API-data. |
| **Organisaties** | *My Organizations* uit Developer Tools: per organisatie de apps, leden met rol en totalen. |
| **Homeys** | De Homeys die aan je account gekoppeld zijn. Je kunt apparaten bedienen, flows en advanced flows starten, apps herstarten en hun instellingen bekijken, en Logic-variabelen, de tijdlijn en systeeminfo openen. Er is een Web API Playground, en alle Developer Tools-tools zijn beschikbaar: Pairing, Zigbee, Z-Wave, RF, IR, BLE, Images en Videos. |
| **Account** | Accounts wisselen, toevoegen en afmelden, net als bij Facebook. Daarnaast licht/donker/automatisch, My API Clients, Webhooks, PAT's, de API-playgrounds en de volledige Developer Tools-site. |

Ook in de app:

- Een splashscreen met draaiend Homey-logo dat naadloos aansluit op het launch screen.
- Het design van Developer Tools en homey.app: een donker oppervlak met kaarten, accent #0082FA en verloopknoppen van blauw naar cyaan. De app is volledig licht en donker te gebruiken.

## Inloggen

**Inloggen met Homey.** Je logt in met het e-mailadres en wachtwoord van je Homey-account, op Athoms eigen inlogpagina via Developer Tools. Je hoeft geen API Client of secret in te stellen.

- Elk account logt in met een eigen, geïsoleerde websessie. Zo kun je meerdere accounts naast elkaar bewaren.
- De sessie wordt bewaard in de iOS-sleutelhanger en ververst automatisch: Developer Tools ververst zijn eigen token.

**Personal Access Token.** Dit is de alternatieve manier, dezelfde als in de Developer Checker Homey-app.

## Bouwen

1. Open `HomeyDevTools.xcodeproj` in **Xcode 16+**.
2. Kies onder *Signing & Capabilities* je **Team**. De bundle-id is `nl.lrvdlinden.homeydevtools`.
3. Kies een iPhone of simulator en druk op ▶︎.

Je hebt geen dependencies nodig: de app gebruikt SwiftUI, Charts, WebKit en CryptoKit.

## Architectuur

```
HomeyDevTools/
├─ App/          Entry point, splash, tabs, PortfolioStore, Config
├─ Core/         Theme (licht/donker), flexibele JSON, HTTP, Keychain, JWT
├─ API/          AuthManager (multi-account), WebSession, AppsAPI, HomeyClient
├─ Models/       DevApp, DevBuild, DevCrash, DevOrganization, HomeyRef, HomeyDevice, …
└─ Views/        Login, Dashboard, Apps, Organisaties, Homey, Web, Account, Components
```

De app praat met deze endpoints:

- Accounttoken → `POST api.athom.com/delegation/token?audience=apps` → `apps-api.athom.com/api/v1/…` voor apps, orgs, builds, crashes en stats.
- Accounttoken → `delegation/token?audience=homey` → `POST <homey>/api/manager/users/login` → Homey Web API.
- `api.athom.com/user/me` voor het profiel en de gekoppelde Homeys, en `/user/me/client` voor de API Clients.

## Status

Versie 1.0.0 is zonder compiler gebouwd en is nog niet in Xcode gecompileerd. Meld buildfouten graag via een issue.
