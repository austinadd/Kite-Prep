# Kite Prep

SAT and PERT practice: a Bluebook-style question bank, a Desmos Lab with replays and a practice pad, animated videos for every math question, PERT test-day prep, and word cards. Your progress, scores, and test date stay on your device.

## iPhone app

GitHub's free Mac runners build an **unsigned** `.ipa` from the Xcode project in `ios/` (see `.github/workflows/build-ios.yml`). It is attached to the **ipa** release:

https://github.com/austinadd/Kite-Prep/releases/tag/ipa

An unsigned `.ipa` won't install by tapping it. A sideloading tool signs it with your Apple ID as it installs it. On Windows, Sideloadly works with a free Apple ID:

1. Install Sideloadly and the iTunes and iCloud apps it asks for, then plug in your iPhone.
2. Drag `KitePrep-unsigned.ipa` into Sideloadly, sign in with your Apple ID, and press Start.
3. On the iPhone, turn on **Developer Mode** (Settings > Privacy & Security) if iOS asks, and trust your Apple ID under Settings > General > VPN & Device Management.

With a free Apple ID the app stops opening after 7 days until you sideload it again (your progress stays), and you can have up to 3 sideloaded apps at once.

## Web version

https://austinadd.github.io/Kite-Prep/ works in any browser. On iPhone, open it in Safari and tap Share > Add to Home Screen. On Android, open it in Chrome and tap Install app.

## Moving progress between versions

In Settings > Move your progress, tap **Copy my progress code** on one device and paste it into Kite Prep on the other. It adds to what's there and never erases anything.

## Files

- `index.html`: the whole web app; `ios/KitePrep/web/` has the same app for the iPhone build
- `manifest.webmanifest`, `icons/`, `sw.js`: home-screen install and offline cache for the web version
- `ios/`: the Xcode project (SwiftUI app that shows the bundled page in a web view)
- `vendor/`, `fonts/`: jQuery, MathQuill and the fonts, kept local so the app works offline; see `LICENSES.md`
