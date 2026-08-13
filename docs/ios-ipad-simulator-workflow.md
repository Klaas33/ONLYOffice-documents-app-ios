# iPad Simulator build and interactive-test workflow

## Decision and platform boundary

This workstation is Ubuntu on WSL2/x64. It has no `xcodebuild` or Swift and, more importantly, it is not macOS. Apple supplies the genuine iOS/iPadOS Simulator only in Xcode on macOS. There is no legitimate Windows/WSL package, Docker image, VM, or Android emulator that can replace it. Android is **not** an equivalent test environment.

**Selected route: an AWS EC2 Mac M2/M2 Pro (or another managed, dedicated Apple Mac) with Xcode, accessed from Windows by SSH plus a VNC/Apple Remote Desktop tunnel.** This is a normal Apple-hardware macOS environment, so it can run the actual Simulator and be controlled interactively. AWS explicitly documents EC2 Mac instances as native macOS on bare-metal Dedicated Hosts and supports SSH or Apple Remote Desktop. Its important operational limit is a 24-hour minimum Dedicated Host allocation. If that is unsuitable, a rented/borrowed physical Mac or a managed dedicated Mac provider is equivalent; do not use a non-Apple macOS VM.

The build is deliberately a **Simulator** build, so it has no signing identity. This is correct: Simulator apps do not need an Apple development certificate. A physical-device build must use your own Apple development team and a unique bundle identifier through Xcode; neither belongs in this repository.

## What is prepared locally

- App source: `develop` at `165ea4d357956d7db1260527b884b7de6f5fcb84`.
- Controlled public package source: `https://github.com/my-onlyoffice-forks/editors-ios-sp.git`, tag `v9.1`, commit `3f9fd21458ccdd0f528a048f81307d57111d7460`.
- Required public sibling folder resource source: `https://github.com/ONLYOFFICE/document-templates.git`, commit `71430c9f183489e8912f54f9dc859e369cf0dfb4` (provides the project-referenced `sample` and `new` folders).
- The project and `Package.resolved` now target that v9.1 package rather than the deleted original URL.
- `tools/verify_editor_artifacts.py` downloads only package-manifest URLs and verifies SHA-256 before retaining a ZIP.
- Local verification completed: **22/22 archives, 287,521,000 bytes total**. The machine-readable record is deliberately ignored at `.local-artifacts/editors-v9.1.0-179/verification-report.json`.
- `tools/build-ipad-simulator.sh` is the reproducible macOS build/launch entry point.

The verifier checks all 22 binary targets (the 21 ONLYOFFICE frameworks and declared Lottie dependency). The app consumes the four products `DocumentConverter`, `DocumentEditor`, `SpreadsheetEditor`, and `PresentationEditor`; SwiftPM/Xcode also independently checks each declared binary-target checksum during resolution.

## Provision the Mac host

1. Allocate an EC2 Mac M2/M2 Pro Dedicated Host and launch a current supported macOS AMI. Restrict its security group to SSH from your public IP; do **not** expose TCP 5900 to the Internet.
2. Connect over SSH using an SSH key held by your SSH agent. Do not copy passwords, Apple IDs, certificates, provisioning profiles, or VNC passwords into this checkout.
3. Sign into the Mac desktop once and install the current Xcode from Apple. Start Xcode once, accept its license, install an iOS Simulator runtime, then select Xcode:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   xcodebuild -version
   xcrun simctl list runtimes
   ```

4. Enable Remote Management/Screen Sharing for the Mac login user in **System Settings > General > Sharing**. Keep access restricted to that user. The host owner can also enable Remote Management through Apple’s supported management tooling; use the macOS UI if policy requires interactive confirmation.
5. On Windows, use a VNC/ARD viewer. TigerVNC was selected as the client, but its installer requires a Windows interactive/UAC confirmation. The unattended `winget` install was cancelled by Windows, so finish it from PowerShell with the visible installer prompt:

   ```powershell
   winget install --id TigerVNC.TigerVNC --exact
   ```

6. From **Windows PowerShell** (not WSL), create a tunnel and keep that terminal open:

   ```powershell
   ssh.exe -N -L 5901:localhost:5900 ec2-user@YOUR_MAC_HOST
   ```

   Then open TigerVNC Viewer and connect to `localhost:5901`. Authenticate interactively as the Mac user. The tunnel keeps the screen-sharing port private while allowing full mouse/keyboard interaction with Simulator from Windows.

## Transfer and run

Transfer the checkout from WSL to the Mac by a private Git remote, `rsync` over SSH, or a normal file transfer. Do not transfer `.local-artifacts`; its contents are cacheable public binaries and will be re-downloaded and reverified on the Mac.

On the Mac, from the repository root:

```sh
./tools/build-ipad-simulator.sh
```

The script performs these steps:

1. Confirms macOS/Xcode availability.
2. Clones the preserved public editor package and public `document-templates` folder resource, detaching both to the recorded commits.
3. Downloads and verifies all 22 archives against `Package.swift` before use.
4. Runs the repository’s Bundler/CocoaPods setup (`Podfile.lock` specifies CocoaPods 1.15.2).
5. Resolves packages from the controlled package URL, creates/boots an available iPad Simulator, builds `Documents-opensource` for `iphonesimulator`, installs it, and launches it.
6. Places a harmless RTF smoke-test file in the installed app’s local Documents container. In the visible app, open **Local Files** and select `ONLYOFFICE-smoke-test.rtf`; this is the manual check that the local document flow enters the native editor.

For a different simulator model, set `SIMULATOR_DEVICE`; for example:

```sh
SIMULATOR_DEVICE='iPad (10th generation)' ./tools/build-ipad-simulator.sh
```

## Known source/configuration limitations

No encrypted configuration was opened, decrypted, copied, or used. The snapshot intentionally omits encrypted service configuration, including its private constants and cloud-service credentials. Therefore cloud login, Firebase/analytics/crash reporting, social sign-in, and service-specific integration cannot be claimed as tested without credentials owned/configured by you. This does not alter the intended local editor binary integration, but a first macOS build may expose additional compile-time stubs needed for this old snapshot. Address those only with harmless local values or by removing the optional integration; never recover the encrypted values.

## Acceptance record to capture on the Mac

Keep the console output from `tools/build-ipad-simulator.sh` plus:

```sh
git rev-parse HEAD
git -C .local-artifacts/editors-ios-sp-v9.1 rev-parse HEAD
cat "$HOME/Library/Caches/ONLYOFFICE/editors-v9.1.0-179/verification-report.json"
xcodebuild -version
xcrun simctl list devices | grep 'ONLYOFFICE iPad test'
```

Record separately whether the app starts, the Local Files view lists the smoke RTF, and the document editor opens it. Do not include account tokens or passwords in that record.
