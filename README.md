# mFanCtl

<img src="thum.jpeg" alt="mFanCtl menu bar display" width="720">

mFanCtl is a macOS menu bar fan control utility for Apple Silicon Macs with
built-in fans. The temperature shown in the menu bar is based on GPU
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

Download the latest DMG from the Releases page, open it, and drag `mFanCtl.app`
to Applications.

On first launch, mFanCtl prepares its privileged helper. macOS may ask you to
allow mFanCtl in the Allow in the Background section under System Settings >
General > Login Items (Login Items & Extensions on newer macOS releases).
Reading the menu bar sensors does not require this privilege; changing fan mode
or RPM requires the helper to be approved and running. If approval is denied or
the helper cannot be used, the status text below the fan mode choices reports
the problem and a mode choice is not considered applied.

If update checks are enabled, mFanCtl contacts the GitHub Releases API at launch
to compare the latest released version.

## Fan modes and safety

mFanCtl uses undocumented Apple SMC interfaces. Sensor availability and fan
behavior may vary by Mac model and macOS version.

The SMC raw fan-mode values currently handled by mFanCtl are `0` (firmware
automatic), `1` (manual), and `3` (system-managed automatic). The Automatic UI
choice accepts a verified `0` or `3`; it does not assume that all Macs use or
return raw mode `3`. Unknown values and failed reads are treated as an error
rather than as proof that the fan is automatic. These meanings are based on
observed behavior, not a public Apple API contract.

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
`.build/mFanCtl.app`. This artifact can test the UI and read-only sensors, but
its privileged fan-control helper intentionally rejects an unsigned client.
It must not be distributed as a release. If `Resources/AppIcon.png` changes, run
`scripts/generate-app-icon.sh` explicitly before packaging so the checked-in
`AppIcon.icns` matches it.

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

## License

MIT
