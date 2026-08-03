# MenuBar FanControl

<img src="thum.jpeg" alt="MenuBar FanControl menu bar display" width="720">

MenuBar FanControl is a macOS menu bar fan control utility for Apple Silicon
Macs with built-in fans. The temperature shown in the menu bar is based on GPU
temperature.

## Requirements

- Apple Silicon Mac with built-in fans
- macOS 14 or later
- macOS Background Items approval is required for the privileged fan control
  helper

Fanless models such as MacBook Air cannot use fan control. Intel Macs are not
supported. Because the SMC fan interface is undocumented, a built-in fan alone
does not guarantee that every control mode is available on every model or macOS
release.

## Features

- Show fan RPM and GPU temperature in the menu bar
- Read Apple Silicon fan speed and temperature sensors
- Switch fan mode between Automatic and Maximum Speed
- Create custom fan presets
- Customize the menu bar display format
- Optional launch at login
- Optional GitHub Releases update check at launch, enabled by default

## Installation

Download the latest DMG from the Releases page, open it, and drag
`MenuBar FanControl.app` to Applications.

When upgrading from a version released before the rename, quit the previous
menu bar app before opening the new app. On first launch, MenuBar FanControl
copies the language, presets, display, update, and launch-at-login preferences;
restores Automatic mode; unregisters the previous fan helper and login item;
and only then offers to move the verified previous app bundle to the Trash.
Do not manually delete the previous app if this migration reports an error.

The active application identifier is
`io.github.jinnyday0719.MenuBarFanControl`. The helper executable, launch daemon,
Mach service, and code-signing identifier use
`io.github.jinnyday0719.MenuBarFanControl.Helper`. Because this is a new background
service identity, macOS may ask for approval again during the upgrade. A
signed migration-only cleanup component temporarily retains the previous
identity so it can restore Automatic and remove the previous helper and login
item during migration; it is not installed or run afterward.

The migration also recognizes the socket-based root helper used by versions
0.1 and 0.2. It verifies Automatic mode with the current controller, stops that
legacy launch daemon, and removes only its fixed executable, plist, socket, and
log paths before completing the rename.

On first launch, MenuBar FanControl prepares its privileged helper. macOS may
ask you to allow MenuBar FanControl in the Allow in the Background section
under System Settings > General > Login Items (Login Items & Extensions on
newer macOS releases). Reading the menu bar sensors does not require this
privilege; changing fan mode or RPM requires the helper to be approved and
running. If approval is denied or the helper cannot be used, the status text
below the fan mode choices reports the problem and a mode choice is not
considered applied.

If update checks are enabled, MenuBar FanControl contacts the GitHub Releases
API at launch to compare the latest released version.

## Fan modes and safety

MenuBar FanControl uses undocumented Apple SMC interfaces. Sensor availability
and fan behavior may vary by Mac model and macOS version.

The SMC raw fan-mode values currently handled by MenuBar FanControl are `0`
(firmware automatic), `1` (manual), and `3` (system-managed automatic). The
Automatic UI choice accepts a verified `0` or `3`; it does not assume that all
Macs use or return raw mode `3`. Unknown values and failed reads are treated as
an error rather than as proof that the fan is automatic. These meanings are
based on observed behavior, not a public Apple API contract.

Manual and Maximum modes use a short safety lease. While one is active, the app
renews the lease; if the app crashes, loses contact with the helper, or stops
renewing it, the helper returns every verified fan to Automatic mode. The app
also reconciles fan state to Automatic at launch, sleep, lock, lid close, and
normal termination.

On Macs that require the `Ftst` unlock (currently observed on M3/M4 systems),
the first Automatic-to-Manual transition can take several seconds while macOS
releases fan control. Switching between presets is fast once Manual mode is
active. Because sleep and lock return the fans to Automatic for safety, the
unlock delay can occur again afterward; the menu status row reports when this
transition is in progress.

Use fan control carefully. If something behaves unexpectedly, switch back to
Automatic mode or restart your Mac.

## Development packaging

Run `scripts/package-menubar-app.sh` to build an unsigned development app at
`.build/MenuBar FanControl.app`. This artifact can test the UI and read-only
sensors, but its privileged fan-control helper intentionally rejects an
unsigned client. It must not be distributed as a release. Packaging generates
`AppIcon.icns` from the tracked `Resources/AppIcon.png`, so a clean clone does
not require a pre-generated icon file.

## Release packaging

The release script requires a Developer ID Application certificate and a
`notarytool` Keychain profile. Create the profile without putting an
app-specific password in shell history:

```sh
xcrun notarytool store-credentials PROFILE_NAME --apple-id APPLE_ID --team-id TEAM_ID
```

`notarytool` securely prompts for the password. Then create the release:

```sh
scripts/package-release.sh --version 1.0.0 --build 1 --notary-profile PROFILE_NAME
```

The command fails unless the arm64 app and helper have matching architectures,
the bundle versions and helper plist identities are correct, both executables
have matching Developer ID teams and hardened-runtime signatures, and both the
app and final DMG pass notarization, stapling, signature validation, and
Gatekeeper assessment. The DMG and app resources both include the MIT license.
Unstripped debug symbols are emitted separately under
`dist/MenuBar-FanControl-VERSION-BUILD.dSYMs`; the signed app contains stripped
executables.

## License

MIT
