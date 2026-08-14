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
5. builds `Documents-opensource` with Xcode 26 for `iphonesimulator`, with signing disabled; and
6. when run interactively on a Mac, creates/boots an iPad Simulator, installs the app, adds a harmless local RTF, and launches the app.

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

After the unsigned Simulator build passes, create a separate device archive on macOS using your Apple Development certificate, registered test-device provisioning profile, development team, and a bundle identifier covered by that profile. Store signing assets only as protected GitHub Actions secrets or install them interactively on the Mac. Never commit or paste certificate/private-key data, provisioning profiles, passwords, or BrowserStack access keys into source or chat.

The resulting development-signed `.ipa` can be uploaded to BrowserStack App Automate and tested on a real iPad. Signing assets are the only unavoidable user-owned prerequisite for this stage.

## Configuration limitations

No encrypted configuration is decrypted or used. Cloud login, Firebase/analytics/crash reporting, social sign-in, and service-specific integrations may remain unavailable without user-owned credentials. Those limitations are separate from startup, local-file flow, and native editor functionality.
