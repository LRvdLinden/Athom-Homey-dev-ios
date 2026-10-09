<p align="center"><img src="HomeyDevTools/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="160" alt="App icon"></p>

# Developer Tools for Homey – iOS

A native SwiftUI app for iPhone and iPad (iOS 17+) that brings [Homey Developer Tools](https://tools.developer.homey.app) to your pocket. It supports multiple accounts, light and dark mode, and four languages.

> Unofficial app. Homey and the Homey logo are trademarks of Athom B.V.

## Features

| Tab | What you get |
|---|---|
| **Home** | Totals across all your apps and organizations: installs, Cloud/Local split, apps in review and average rating. Also an installs-per-app chart, your top apps and apps awaiting certification. |
| **My Apps** | Your own apps with search and sorting. Per app: statistics, install trend (7d/30d/90d/1y/all), the live build with changelog and permissions, all builds, crashes with stack traces, suggestions, paired devices per driver and the raw API data. |
| **Organizations** | *My Organizations* from Developer Tools: apps, members with roles and totals for each organization. |
| **Homeys** | The Homeys linked to your account. Control devices, trigger flows and advanced flows, restart apps and view their settings, and browse Logic variables, the timeline and system info. Includes a Web API Playground and all Developer Tools utilities: Pairing, Zigbee, Z-Wave, RF, IR, BLE, Images and Videos. |
| **Account** | Switch, add and sign out of accounts, like in the Facebook app. Plus light/dark/automatic appearance, language, My API Clients, Webhooks, Personal Access Tokens, the API playgrounds and the full Developer Tools website. |

Also included:

- **Multilingual:** Dutch, English, German and French. The app follows your device language. You can pick a different language for this app only under **Settings → Homey Dev → Language**.
- **Splash screen** with a spinning Homey logo that continues seamlessly from the launch screen.
- **Design** inspired by Developer Tools and homey.app, with a blueprint-style app icon. Fully supports light and dark mode.

## Signing in

**Sign in with Homey.** Use the email address and password of your Homey account, on Athom's own login page through Developer Tools. You don't need to set up an API client or secret.

- Each account signs in with its own isolated web session, so several accounts can be saved side by side.
- Sessions are stored in the iOS Keychain and refresh automatically, because Developer Tools refreshes its own token.

**Personal Access Token.** As an alternative, the same method used by the Developer Checker Homey app. Create a token in Developer Tools under *My Account*.

## Building

1. Open `HomeyDevTools.xcodeproj` in **Xcode 16 or later**.
2. Select your **Team** under *Signing & Capabilities*. The bundle ID is `nl.lrvdlinden.homeydevtools`, and you can change it.
3. Choose an iPhone or simulator and press ▶︎.

There are no third-party dependencies: only SwiftUI, Charts, WebKit and CryptoKit.

## Architecture

```
HomeyDevTools/
├─ App/                    Entry point, splash, tabs, PortfolioStore, Config
├─ Core/                   Theme (light/dark), flexible JSON, HTTP, Keychain, JWT
├─ API/                    AuthManager (multi-account), WebSession, AppsAPI, HomeyClient
├─ Models/                 DevApp, DevBuild, DevCrash, DevOrganization, HomeyRef, HomeyDevice, …
├─ Views/                  Login, Dashboard, Apps, Organizations, Homey, Web, Account, Components
└─ Localizable.xcstrings   Translations (nl source, en, de, fr)
```

The app uses these endpoints:

- Account token → `POST api.athom.com/delegation/token?audience=apps` → `apps-api.athom.com/api/v1/…` for apps, organizations, builds, crashes and statistics.
- Account token → `delegation/token?audience=homey` → `POST <homey>/api/manager/users/login` → Homey Web API.
- `api.athom.com/user/me` for the profile and linked Homeys, and `/user/me/client` for API clients.

## Adding a language

Open `Localizable.xcstrings` in Xcode, click **+** to add a language and translate the strings. Then add the language code to `knownRegions` in the project.

## Changelog

- **1.2.0:** Multilingual app (Dutch, English, German, French) using a String Catalog, plus a language row under Account → Appearance.
- **1.1.0:** New Apple Developer-style app icon with a white Homey ring, a blue blueprint login screen and a spinning Homey logo on the splash screen.
- **1.0.0:** First release: sign in with Homey or a PAT, multiple accounts, Home, My Apps, Organizations, Homeys and Account.

## Feedback

Found a bug or a build error? Please open an [issue](https://github.com/LRvdLinden/Athom-Homey-dev-ios/issues).
