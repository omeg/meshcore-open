# TestFlight Release Guide

This guide describes the current iOS release path for MeshCore Open. Apple changes upload and review requirements over time, so use this as a repository checklist together with [Flutter's iOS release guide](https://docs.flutter.dev/deployment/ios) and [App Store Connect Help](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

## Project facts

- Bundle identifier: `com.monitormx.meshcoreopen`
- Minimum iOS version: 16.4
- Version source: `version:` in `pubspec.yaml` (currently `9.5.0+13`)
- Xcode workspace: `ios/Runner.xcworkspace`
- Privacy policy: publish [docs/PRIVACY_POLICY.md](docs/PRIVACY_POLICY.md) at a public HTTPS URL before distribution

Each App Store Connect upload needs a build number that has not already been uploaded for that version. Update `pubspec.yaml`, or supply `--build-name` and `--build-number` to the build command.

## Requirements

- A Mac with a currently supported Xcode version and command-line tools
- A Flutter SDK compatible with the repository lockfile (Flutter 3.44+/Dart 3.12+ at the time of writing)
- Membership in the Apple Developer Program
- An App Store Connect user with permission to create/upload builds
- A registered App ID and App Store Connect app record for `com.monitormx.meshcoreopen`
- Signing certificates/profiles, normally managed automatically by Xcode

## 1. Prepare and validate

From the repository root:

```bash
flutter pub get
flutter analyze
flutter test
```

Then open the workspace:

```bash
open ios/Runner.xcworkspace
```

In Xcode, select the Runner target and verify:

- Your Apple Developer team is selected under **Signing & Capabilities**.
- The bundle identifier is correct and automatic signing reports no errors.
- The deployment target remains iOS 16.4 unless a deliberate project change says otherwise.
- Bluetooth descriptions and capabilities required by the app are present.
- The Release configuration uses the intended app icon and display name.

Test a release build on at least one physical device. The simulator cannot validate BLE companion behavior.

## 2. Set a release version

Use semantic version plus build number in `pubspec.yaml`:

```yaml
version: 9.5.0+14
```

Increment the build number for every upload. Commit the version change when the build is intended to be reproducible from source.

## 3. Build the archive and IPA

The Flutter command produces an Xcode archive in `build/ios/archive/` and an App Store IPA in `build/ios/ipa/`:

```bash
flutter build ipa --release
```

If automatic export cannot resolve signing, open the generated `.xcarchive` in Xcode Organizer, validate it, and use **Distribute App → App Store Connect**. Do not open `Runner.xcodeproj`; use the workspace so CocoaPods dependencies are included.

## 4. Upload

Apple supports upload from Xcode Organizer, Transporter, or its command-line/API tooling. The simplest paths are:

- In Xcode Organizer, select the archive, choose **Distribute App**, validate, and upload.
- In Transporter, drop in the IPA from `build/ios/ipa/` and deliver it.

The bundle identifier and marketing version associate the upload with the App Store Connect record; the build number uniquely identifies the build. Wait for App Store Connect processing and resolve any warning, failure, missing-compliance, or metadata action shown on the build.

## 5. Complete TestFlight information

In the app's **TestFlight** tab:

1. Select the processed build.
2. Supply beta app description, feedback contact, and **What to Test** notes.
3. Complete privacy and export-compliance questions accurately.
4. Add the build to an internal or external testing group.

MeshCore Open uses cryptography in its protocol and dependencies. Do not copy a canned yes/no export-compliance answer from an older release. Apple requires the publisher to determine whether documentation or an exemption applies; follow [Apple's current export-compliance guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance) and obtain qualified advice when needed.

Internal testing supports up to 100 App Store Connect users with appropriate access. External testing supports up to 10,000 people and can require TestFlight App Review, particularly for the first build in a group. A TestFlight build is available for testing for up to 90 days. See [Apple's TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview).

## 6. Suggested test notes

Keep the notes scoped to the build. For a broad fork release, ask testers to cover:

- BLE connection/disconnection and background reconnect
- TCP companion connection on iOS
- Direct messages, channels, reactions, replies, share links, and resend/retry behavior
- Contact/discovery persistence and identity changes
- Maps, location pins, line-of-sight, and offline cache
- Repeater login, live telemetry, CLI, neighbors, and settings
- Telemetry-log/InfluxDB features only when the tester uses the [omeg MeshCore firmware fork](https://github.com/omeg/meshcore)

Include a warning if the build migrates identity-scoped storage or requires newer companion firmware.

## App Store submission notes

TestFlight distribution does not replace App Store product metadata. Before a public App Store submission, provide the required privacy-policy URL, app privacy answers, descriptions, support URL, age rating, categories, and current screenshots. Apple's screenshot requirements are maintained in [App Store Connect Help](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots); if the UI is identical across sizes, Apple can scale the highest-resolution screenshots to smaller sizes.

Use the fork issue tracker as the support URL unless a dedicated support page exists:

```text
https://github.com/omeg/meshcore-open/issues
```

## Common failures

- **Bundle identifier unavailable or app not found:** Confirm the App ID, App Store Connect record, and Xcode target all use `com.monitormx.meshcoreopen` under the same team.
- **Signing/provisioning error:** Let Xcode refresh automatic signing, verify the selected team and device/App Store distribution method, then rebuild.
- **Duplicate build number:** Increment the `+build` value or pass a new `--build-number`.
- **Archive contains missing Pods/frameworks:** Build from `Runner.xcworkspace`, rerun `flutter pub get`, and regenerate the archive.
- **Build remains unavailable:** Check its processing status, warnings, export-compliance state, and email from App Store Connect before uploading another copy.
- **BLE cannot be tested:** Use a physical iPhone/iPad with Bluetooth permission granted and a compatible MeshCore companion nearby.
