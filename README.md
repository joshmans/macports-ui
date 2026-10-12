# MacPorts UI

A native macOS app for [MacPorts](https://www.macports.org). It prefers prebuilt binaries, so most installs finish in seconds instead of compiling from source.

**Status:** 0.9, a release candidate for 1.0.

## Features

- **Outdated:** see which ports have updates and upgrade them.
- **Installed:** browse what you have, with what each port is and what depends on it.
- **Browse:** search the whole ports tree and install with a variant picker.
- **Activity:** a queue of running and finished jobs with live output.
- **Migrate:** move Homebrew formulae to MacPorts. Each port is installed prebuilt-only and verified before the Homebrew copy is removed.
- **Privileged helper (optional):** a small background service so you aren't asked for your administrator password on every change.

## Requirements

- macOS 13 or later
- [MacPorts](https://www.macports.org/install.php) installed

## Install

1. Download `MacPorts-UI-0.9.dmg` from the [latest release](https://github.com/joshmans/macports-ui/releases/latest).
2. Open the DMG and drag **MacPorts UI** onto the **Applications** shortcut.
3. Eject the DMG and launch MacPorts UI from Applications.

The app is signed with a Developer ID and notarized by Apple, so it opens without Gatekeeper warnings.

### Optional: enable the privileged helper

Without the helper, every install, upgrade or uninstall asks for your administrator password. To avoid that, open the helper settings (the shield button in the toolbar, or the app's Settings) and enable it. macOS will ask you to approve the background item in System Settings → General → Login Items.

The helper only runs `install`, `upgrade`, `uninstall` and `selfupdate`. Because MacPorts runs port build scripts as root, only install ports you trust.

## Build from source

You need the Swift toolchain (Xcode or the Command Line Tools). There is no Xcode project.

```bash
git clone https://github.com/joshmans/macports-ui.git
cd macports-ui
scripts/make-app.sh release
open "build/MacPorts UI.app"
```

This builds an ad-hoc signed app without the helper, so port changes use the password prompt. To build with the helper, sign with your own Developer ID certificate. Also change `APP_ID` in `scripts/make-app.sh` and the matching name in `Helper/com.otstechs.macportsui.helper.plist` to your own bundle identifier.

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/make-app.sh release
```

Add `NOTARY_PROFILE=<profile>` (from `xcrun notarytool store-credentials`) to notarize and staple too. To package a DMG afterwards:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=<profile> scripts/make-dmg.sh
```

### Tests

```bash
swift test --package-path MacPortsKit
swift test --package-path MacPortsUI
```

## Known limitations

- The Homebrew switch has only been tested against a fake backend, not on a live Homebrew install.
- Disk usage isn't shown yet.
- Activity history isn't kept between launches, and running jobs can't be cancelled.
- Variants of dependencies can't be chosen, only those of the port you install.

## Layout

- `MacPortsKit/`: the library (running `port`, parsing, install planning, helper client) and the helper executable
- `MacPortsUI/`: the SwiftUI app
- `Helper/`: launch daemon plist
- `scripts/`: app, icon and DMG build scripts

## License

[MIT](LICENSE)
