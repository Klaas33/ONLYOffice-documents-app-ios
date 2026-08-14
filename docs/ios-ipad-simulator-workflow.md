# iPad build and testing workflow

## Platform boundary

This workstation is Linux under WSL2 on Windows. Apple’s iOS/iPadOS Simulator is part of Xcode and runs only on macOS. Android, a Linux VM, or a Windows “iOS emulator” is not equivalent.

The GitHub Actions workflow therefore uses an Apple-hosted macOS runner for an unsigned Simulator build. Interactive testing from Windows can use either:

1. a dedicated/rented Mac running Xcode Simulator, reached through SSH plus Screen Sharing/VNC; or
2. BrowserStack real iPads, which require a development-signed `.ipa` and provisioning profile owned by the user.

A Simulator `.app` cannot be uploaded to BrowserStack as a real-device app. `agent-device` can automate a reachable device session, but does not replace Apple code signing or turn a Simulator build into a device build.

## Reproducible source and binary inputs

- App wrapper: public preserved repository `sanyaade-teachings/ONLYOffice-documents-app-ios`, `master` commit `32f08f75327846afc491c5a1e449e8dff9d02fc8`.
- App version declared by `Documents.opensource.plist`: **9.2.0**.
- Editor package mirror: `https://github.com/my-onlyoffice-forks/editors-ios-sp.git`.
- Selected editor package commit: `0c584d936384402f090f1d66823c42186a2ed972`.
- That commit is named `release/v9.3.0` in the mirror, but its manifest points to **hotfix v9.2.1 build 181**, not a v9.3 editor release.
- Editor artifact root: `https://s3.eu-west-1.amazonaws.com/repo-doc-onlyoffice-com/ios/editors/hotfix/v9.2.1/181/`.
- Selected `Package.swift` SHA-256: `4219f1a785fac9b182f8a089c4af65b252bc34e6f94169fbf3c226e158f855e3`.
- Package products: `DocumentConverter`, `DocumentEditor`, `PresentationEditor`, and `SpreadsheetEditor`.
- Binary targets: 22, including the declared Lottie binary dependency.
- Local integrity check: **22/22 verified**, **289,948,300 bytes**, with no checksum failures.
- Public template resource repository: `https://github.com/ONLYOFFICE/document-templates.git`, commit `71430c9f183489e8912f54f9dc859e369cf0dfb4`.

The apparent editor `release/v9.3.0` branch is deliberately described by its real binary version everywhere in this workflow. If its API does not compile with the v9.2.0 app wrapper, the controlled fallback is editor tag `v9.2` / release `v9.2.0/180`, not an invented v9.3 engine.

## Integrity and build process

`tools/build-ipad-simulator.sh`:

1. checks out the editor package and document templates at immutable commits;
2. runs `tools/verify_editor_artifacts.py`, which downloads every manifest-declared ZIP and retains it only when its SHA-256 equals the manifest checksum;
3. installs the CocoaPods dependencies pinned by `Gemfile.lock`;
4. resolves Swift packages from the public mirror pinned in the Xcode project and `Package.resolved`;
5. normally builds `Documents-opensource` with Xcode 26 for `iphonesimulator`, with signing disabled;
6. with `BUILD_PLATFORM=device`, builds a development-signed arm64 IPA using a new user-owned bundle ID and no private ONLYOFFICE entitlements; and
7. when run interactively on a Mac, creates/boots an iPad Simulator, installs the app, adds a harmless local RTF, and launches the app.

GitHub Actions sets `BUILD_ONLY=1`, so it compiles and uploads the Simulator `.app` plus `verification-report.json` without trying to allocate a GUI Simulator.

Run on a Mac from the repository root:

```sh
./tools/build-ipad-simulator.sh
```

Run build-only validation:

```sh
BUILD_ONLY=1 ./tools/build-ipad-simulator.sh
```

## Interactive Mac-hosted Simulator from Windows

On a legitimate Apple Mac host:

1. Install and launch Xcode 26 once, accept its license, and install an iOS Simulator runtime.
2. Select Xcode and initialize components:

   ```sh
   sudo xcode-select -s /Applications/Xcode_26.0.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   xcodebuild -version
   xcrun simctl list runtimes
   ```

3. Enable Screen Sharing/Remote Management only for the intended Mac user. Do not expose TCP 5900 directly to the Internet.
4. From Windows PowerShell, create an SSH tunnel:

   ```powershell
   ssh.exe -N -L 5901:localhost:5900 USER@MAC_HOST
   ```

5. Connect a VNC/ARD client to `localhost:5901`, then run the build script on the Mac.

## BrowserStack real-iPad stage

BrowserStack requires an iOS `.ipa` built for a real arm64 device. It re-signs uploaded iOS apps by default with its own provisioning profile. BrowserStack documents that this strips most entitlements; only basic signing/keychain entitlements remain. The device workflow therefore clears the preserved app's push, iCloud, and original-team keychain entitlements. Those optional service features are unavailable, while startup, local files, and native editors remain valid test targets.

The workflow `.github/workflows/ios-browserstack-device.yml` builds a development-signed IPA and uploads it directly to BrowserStack. It deliberately does **not** publish the IPA as a public-repository Actions artifact because an IPA embeds its provisioning profile.

### One-time Apple setup

A paid Apple Developer Program membership with permission to create signing assets is required. In the Apple Developer portal, create:

1. an explicit App ID owned by your team, using a new identifier such as `com.yourname.onlyoffice.documents` (do not use ONLYOFFICE's identifier);
2. an Apple Development certificate exported with its private key as a password-protected `.p12`; and
3. an **iOS App Development** provisioning profile for that exact App ID and certificate.

Do not enable iCloud, push notifications, Sign in with Apple, associated domains, or other optional capabilities for this local-editor test build.

In the fork's GitHub page, open **Settings → Secrets and variables → Actions** and add:

Variables (not credentials):

- `APPLE_TEAM_ID`: your 10-character Apple team ID.
- `IOS_BUNDLE_ID`: the exact explicit App ID from above.

Repository secrets:

- `BUILD_CERTIFICATE_BASE64`: base64 of the `.p12` file.
- `P12_PASSWORD`: the `.p12` export password.
- `BUILD_PROVISION_PROFILE_BASE64`: base64 of the `.mobileprovision` file.
- `BROWSERSTACK_USERNAME`: BrowserStack Automate username.
- `BROWSERSTACK_ACCESS_KEY`: BrowserStack Automate access key.

Use the GitHub browser UI; never paste these values into chat, source, command arguments, or logs. Then open **Actions → Build and upload ONLYOFFICE iPad device app → Run workflow** on branch `build/onlyoffice-ipad-v9.2.1`.

The workflow checks that the profile's team and explicit application identifier match the variables, verifies the signed arm64 IPA, verifies all editor ZIP checksums again, and uploads the IPA to:

```text
POST https://api-cloud.browserstack.com/app-automate/upload
custom_id=onlyoffice-documents-ios-v9.2.0
```

The successful workflow summary records the returned `bs://...` app URL and the IPA SHA-256, but no credentials or signing files.

### Interactive testing through agent-device from WSL

`agent-device` 0.20.8 is installed locally and includes a BrowserStack provider. In a private WSL terminal, collect the credentials without putting the access key in shell history:

```sh
read -r -p 'BrowserStack username: ' BROWSERSTACK_USERNAME
read -r -s -p 'BrowserStack access key: ' BROWSERSTACK_ACCESS_KEY; printf '\n'
export BROWSERSTACK_USERNAME BROWSERSTACK_ACCESS_KEY
```

Use the exact iPad model and iOS version offered by your BrowserStack account, plus the `bs://...` value from the successful workflow:

```sh
agent-device connect browserstack --platform ios \
  --device 'EXACT BROWSERSTACK IPAD NAME' \
  --provider-os-version 'EXACT IOS VERSION' \
  --provider-app 'bs://APP-ID-FROM-WORKFLOW'
```

`connect` validates the credentials, device, and app without allocating a paid session. Follow the exact session name printed by the command. `open` creates the hosted App Automate session:

```sh
agent-device open com.yourname.onlyoffice.documents --session SESSION-NAME
agent-device snapshot -i --session SESSION-NAME
```

After testing, release the hosted device and remove credentials from that shell:

```sh
agent-device close --session SESSION-NAME
agent-device artifacts --json --session SESSION-NAME
agent-device disconnect --session SESSION-NAME
unset BROWSERSTACK_USERNAME BROWSERSTACK_ACCESS_KEY
```

## Configuration limitations

No encrypted configuration is decrypted or used. Cloud login, Firebase/analytics/crash reporting, social sign-in, and service-specific integrations may remain unavailable without user-owned credentials. Those limitations are separate from startup, local-file flow, and native editor functionality.
