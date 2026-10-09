<p align="center"><img src="HomeyDevTools/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="160" alt="App icon"></p>

# Developer Tools for Homey – iOS

A native SwiftUI app for iPhone, iPad and Apple TV (iOS/iPadOS 17+, tvOS 17+) that brings [Homey Developer Tools](https://tools.developer.homey.app) to your pocket. It supports multiple accounts, light and dark mode, and four languages.

> Unofficial app. Homey and the Homey logo are trademarks of Athom B.V.

## Screenshots

> Illustrative mockups with fictional data. The real app shows your own account, apps and Homeys.

<table>
  <tr>
    <th>iPhone (iOS)</th>
    <th>iPad (iPadOS)</th>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/ios.png" width="260" alt="iPhone – Home dashboard"></td>
    <td align="center" valign="top"><img src="docs/screenshots/ipados.png" width="520" alt="iPad – sidebar and Home dashboard"></td>
  </tr>
</table>

**Apple TV (tvOS)**: full-screen dashboard that refreshes every 5 minutes

<p align="center"><img src="docs/screenshots/tvos.png" width="820" alt="Apple TV – dashboard"></p>

**Widgets**: Installs (small and medium), Top apps and Review & crashes

<p align="center"><img src="docs/screenshots/widgets.png" width="720" alt="Home screen widgets"></p>

## Features

| Tab | What you get |
|---|---|
| **Home** | Totals across all your apps and organizations: installs, Cloud/Local split, apps in review and average rating. Also an installs-per-app chart, your top apps and apps awaiting certification. |
| **My Apps** | Your own apps with search and sorting. Per app: statistics, install trend (7d/30d/90d/1y/all), the live build with changelog and permissions, all builds, crashes with stack traces, suggestions, paired devices per driver and the raw API data. Build actions: publish to Test/Live, submit for certification and retract from review, plus the reviewer comment thread. Reply to reviews and manage email notifications. |
| **Organizations** | *My Organizations* from Developer Tools: apps, members with profile pictures and roles, and totals for each organization. Owners and admins can invite, re-role and remove members. |
| **Homeys** | The Homeys linked to your account. Control devices, trigger flows and advanced flows, restart apps and view their settings, and browse Logic variables, the timeline and system info. Includes a Web API Playground and native tools: System, Insights, Zigbee, Z-Wave, Bluetooth LE, RF, Infrared, Images and Videos. Pairing opens on the website. |
| **Account** | Status notifications for every build change (draft, Test, in review, approved, rejected, Live). Switch, add and sign out of accounts, like in the Facebook app. Plus light/dark/automatic appearance, language, My API Clients, Webhooks, Personal Access Tokens, the API playgrounds and the full Developer Tools website. |

Also included:

- **Multilingual:** Dutch, English, German and French. The app follows your device language. You can pick a different language for this app only under **Settings → Homey Dev → Language**.
- **Splash screen** with a spinning Homey logo that continues seamlessly from the launch screen.
- **Design** inspired by Developer Tools and homey.app, with a blueprint-style app icon. Fully supports light and dark mode.

## Widgets

Add them from the home screen (long-press → **+** → *Homey Dev*):

| Widget | Sizes | Shows |
|---|---|---|
| **Installs** | Small, Medium, Large | One app (choose via *Edit Widget*) or all apps: installs, 7/30-day change, Homey Insights-style chart, Cloud/Local, rating, devices, suggestions, crashes and fastest growers |
| **Top apps** | Medium, Large | Your top 3 or 6 apps with icon, 30-day trend line, installs, 7-day change, version, rating, devices and review/crash markers |
| **Review & crashes** | Small, Medium, Large | Apps in review, crashes per app, suggestions and paired devices |

The app shares a snapshot with the widgets through the App Group `group.nl.lrvdlinden.homeydevtools`. The widgets don't need a login, and their data updates each time the app refreshes.

## Apple TV

There are three ways to get your accounts onto the Apple TV:

1. **Pair over Wi-Fi (recommended).** Open **Homey Dev** on the Apple TV; it shows a 4-digit code. In the iPhone app, go to **Account → Apple TV → Pair over Wi-Fi**, pick your Apple TV and enter the code. The accounts are sent directly and encrypted over the local network (Multipeer Connectivity), so iCloud is not needed.
2. **Personal Access Token.** On the Apple TV, choose **Enter token** and paste a token from Developer Tools → My Account. Your iPhone offers its keyboard for this.
3. **iCloud Keychain.** In the iPhone app, turn on **Account → Apple TV → Share with Apple TV**. This syncs through iCloud Keychain and can take a few minutes; both devices must use the same Apple Account.

For each account the iPhone uses its Personal Access Token (like *Reveal* in Developer Tools → My Account), because web sessions expire.

The TV app shows a dashboard that refreshes every 5 minutes, plus My Apps, Organizations and Account. It is read-only, and you scroll through every screen with the Siri Remote.

## Push notifications

There are two ways to get status notifications (**Account → Notifications**):

| | On this device | Direct via push (OneSignal) |
|:--|:--|:--|
| How | The app checks when it refreshes and with Background App Refresh | A GitHub Actions job checks every 10 minutes and sends a push |
| Delay | Minutes to hours (iOS decides) | About 10 minutes |
| Setup | None | One-time, see below |

**One-time setup for direct push**

1. In OneSignal, add your Apple Push key (*Settings → Platforms → Apple iOS*).
2. In this repository, go to **Settings → Secrets and variables → Actions** and add two secrets:
   - `ONESIGNAL_API_KEY`: your OneSignal REST API key (*OneSignal → Settings → Keys & IDs*).
   - `HOMEY_PATS`: the Personal Access Token of each Homey account to watch (*Developer Tools → My Account*), one per line.
3. Under **Actions → Status push**, click **Run workflow** once. The first run only records the current status; after that, every change sends a push.
4. In the app, turn on **Direct via push (OneSignal)** and allow notifications.

The OneSignal App ID is built into the app. The API key and tokens stay in GitHub secrets. GitHub pauses scheduled workflows after 60 days without activity in the repository; re-enable it under **Actions** if that happens.

## Signing in

**Sign in with Homey.** Use the email address and password of your Homey account, on Athom's own login page through Developer Tools. You don't need to set up an API client or secret.

- Each account signs in with its own isolated web session, so several accounts can be saved side by side.
- Sessions are stored in the iOS Keychain and refresh automatically, because Developer Tools refreshes its own token.

**Personal Access Token.** As an alternative, the same method used by the Developer Checker Homey app. Create a token in Developer Tools under *My Account*.

## Building

1. Open `HomeyDevTools.xcodeproj` in **Xcode 16 or later**.
2. Select your **Team** under *Signing & Capabilities* for all three targets: **HomeyDevTools**, **HomeyDevToolsWidget** and **HomeyDevToolsTV**. The bundle IDs are `nl.lrvdlinden.homeydevtools` (iPhone, iPad and Apple TV share it, so it is one App Store app with universal purchase) and `nl.lrvdlinden.homeydevtools.widgets`. Xcode registers the App Group automatically.
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

## What's new

**1.3.2** adds ⚡️ **direct push notifications** through OneSignal: get notified within minutes when a build is uploaded, put in Test, submitted, approved, rejected or published to Live, even when the app is closed. See [Push notifications](#push-notifications) for the one-time setup.

📜 See the full history in **[CHANGELOG.md](CHANGELOG.md)**.

## Feedback

Found a bug or a build error? Please open an [issue](https://github.com/LRvdLinden/Athom-Homey-dev-ios/issues).
