# Rockimals — iOS App Store Release Guide

A first-timer's walkthrough, written for this project specifically (Flutter app,
kids' app, NASA API key via `--dart-define`). Follow it top to bottom.

---

## 0. One-time machine setup

You don't have Xcode yet (the `Simulator` error told us that). Install it first:

1. Install **Xcode** from the Mac App Store (~10 GB, takes a while).
2. Then in Terminal:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```

3. Install **CocoaPods** (Flutter's iOS dependency manager):

   ```bash
   brew install cocoapods     # or: sudo gem install cocoapods
   ```

4. Verify everything: `flutter doctor` — the Xcode section should be green.

---

## 1. Give the app its identity

**Bundle ID** — the app's unique reverse-DNS name, e.g. `com.ibrahimuylas.rockimals`.
Pick one now; it can never change after release.

**Display name & icon:**

- The name under the icon comes from `ios/Runner/Info.plist` (`CFBundleDisplayName`) — set it to `Rockimals`.
- App icon: you need a full icon set including a 1024×1024 marketing icon.
  Easiest route: add the `flutter_launcher_icons` dev package, point it at a
  1024×1024 PNG of Rusty, and run
  `dart run flutter_launcher_icons`.

**Version** lives in `pubspec.yaml`: `version: 1.0.0+1` (`1.0.0` is what users
see; `+1` is the build number — bump it every upload).

---

## 2. Set up signing in Xcode

1. `open ios/Runner.xcworkspace` (the **workspace**, not the .xcodeproj).
2. Select the **Runner** target → **Signing & Capabilities** tab.
3. Tick **Automatically manage signing**, choose your **Team** (your Apple
   Developer account), and enter your bundle ID.
4. Xcode creates the signing certificate and provisioning profile for you.
   If prompted, sign in with your Apple ID under Xcode → Settings → Accounts.

Sanity check: plug in an iPhone if you have one and `flutter run` — proves
signing works before you attempt a release build.

---

## 3. Create the app record in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**.
2. Platform: iOS. Name: **Rockimals** (must be unique on the store).
   Language, your bundle ID from step 2, and an SKU (any internal string, e.g. `rockimals-001`).

---

## 4. Build the release with your NASA API key

This is where the key goes in — it's baked into the binary at build time:

```bash
cd ~/Projects/rockimals
flutter build ipa --dart-define=NASA_API_KEY=your_real_key_here
```

Output: `build/ios/ipa/rockimals.ipa` (or `Runner.ipa`).

Notes on the key:

- **Never** hardcode it in `app_config.dart` or commit it — the `--dart-define`
  seam exists so it stays out of git.
- NASA keys are free and rate-limited **per key** (~1,000 requests/hour shared
  across *all* your users). Your app's feed cache + offline fallback degrade
  gracefully if that's ever hit, so this is fine for v1 — just don't remove the
  caching layer.

---

## 5. Upload the build

Easiest way: the **Transporter** app (free, Mac App Store).

1. Open Transporter, sign in with your Apple ID.
2. Drag `build/ios/ipa/*.ipa` in → **Deliver**.
3. Wait ~10–30 min; the build appears in App Store Connect → your app →
   **TestFlight** tab (it may say "Processing" first).
4. First upload: answer the export-compliance question (standard HTTPS only →
   "None of the algorithms mentioned above" / exempt).

---

## 6. Test through TestFlight (recommended)

In the TestFlight tab, add yourself as an internal tester, install the
**TestFlight** app on your iPhone, and run the real release build. This is the
single best way to catch issues before review. Check: live NASA data loads
(proves the API key made it into the build), offline mode, sounds, parent gate.

---

## 7. Fill in the store listing

In App Store Connect → your app → the **1.0 Prepare for Submission** page:

- **Screenshots**: required for 6.9" and 6.5" iPhones (and 13" iPad if the app
  runs on iPad). Take them in the iOS Simulator (Cmd+S saves a screenshot).
- **Description, keywords, support URL.**
- **Privacy policy URL** — required. Yours can be one page: "Rockimals collects
  no personal data, has no accounts, no ads, no third-party analytics." Host it
  free on GitHub Pages.
- **App Privacy** (nutrition labels): declare **Data Not Collected** — true for
  this app, and a big plus for review.
- **Age rating**: Apple's questionnaire was overhauled in 2025–26 (new tiers
  4+/9+/13+/16+/18+, and as of July 2026 it includes social-media questions —
  answer "no" to those). Rockimals should land at **4+**.

### Kids Category (important for this app)

Opting into the **Kids Category** (choose the age band, e.g. 6–8) is the right
home for Rockimals, but it triggers Apple's strictest rules (guideline 1.3):

- No third-party analytics/ads that transmit kids' data — ✅ you have none.
- **All external links must sit behind a parental gate** — ✅ your NASA/JPL
  links are already gated. Reviewers *will* test this by tapping the links.
- No personal data collection — ✅.

Your guardrails were designed for exactly this, so you're in good shape — but
expect the reviewer to poke at the parent gate specifically.

---

## 8. Submit for review

Select the build you uploaded, answer the remaining questions, **Add for
Review** → **Submit**. Typical review time is 1–2 days; kids' apps sometimes get
an extra look. If rejected, you get a specific reason in Resolution Center —
fix, bump the build number (`+2`), rebuild with the same `--dart-define` flag,
re-upload, resubmit. Almost everyone gets at least one rejection on a first
app; it's normal.

Once approved, you choose manual or automatic release. 🎉

---

## Later: Android

When you do Google Play: same idea — `flutter build appbundle
--dart-define=NASA_API_KEY=...`, plus a keystore for signing and the Play
Console listing. Note Google requires new personal accounts to run a closed
test with 12 testers for 14 days before public release. Ask me when you get
there.

## Quick reference

```bash
# Release build with key
flutter build ipa --dart-define=NASA_API_KEY=YOUR_KEY

# Before each new upload
#   1. bump build number in pubspec.yaml (1.0.0+1 -> 1.0.0+2)
#   2. rebuild with the flag above
#   3. drag the .ipa into Transporter
```
