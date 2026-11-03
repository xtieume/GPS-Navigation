# GPSNav

GPSNav is a location simulator for jailbroken iOS 16.0 and later on arm64/arm64e. It supports rootless and rootful jailbreaks. Author: Tieu Me.

## Features and use

- Tap or long-press the map in **Fixed** mode to choose a coordinate, then turn on **Spoof location**. In **Random** mode the selected point is the center; set the radius in meters and interval in seconds under **Random**.
- In **Route** mode tap A and then B. MapKit calculates a road route; use **Speed / route** to select automobile or walking directions, speed in km/h, and reverse loop. Turn on spoofing after the route loads. Tap again to start a new route.
- Search for a place and select a result; **Search history** keeps the last 20 searches. **Bookmarks** and **Routes** save, apply, and delete locations and routes. Settings lets you edit a comma-separated bundle ID blacklist and view About.
- SpringBoard runs the simulation in the background and restores its progress after a respring. The map shows the published engine position.

## Install

Choose the rootless `iphoneos-arm64` or rootful `iphoneos-arm` deb for your jailbreak. Transfer it to the device and install with Sileo or Filza. Respring to load the tweak into SpringBoard and restart target apps. Enable tweak injection in the jailbreak if required. Remove the package with your package manager.

## Limitations

- Requires a compatible jailbreak and tweak loader; this is not an App Store app. No device runtime verification is included in the build.
- Only Core Location manager APIs in injected app processes are substituted; other sources, system daemons, server-side checks, heading, and apps that block injection are unaffected. Apps may detect simulated or inconsistent location data.
- The blacklist is read once per app launch. A sandbox may prevent reading the shared plist, in which case that app is not excluded; restart affected apps after editing it.
- MapKit search and directions need network access and availability varies by region. Random mode jumps rather than traveling between points. Route movement is tick-based and may cut across very short polyline segments.
- The app writes an unsandboxed preferences file; enabling the required private entitlements depends on the jailbreak. Current position/progress is stored separately in the same preferences directory to avoid overwriting settings.

## Build

Install Xcode with an iPhoneOS SDK, Theos at `~/theos`, and `ldid`, GNU make, and `dpkg` (e.g. `brew install ldid make dpkg`). From a checkout whose path contains no spaces:

```sh
export THEOS="$HOME/theos"
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make clean
make package FINALPACKAGE=1
```

Packages appear in `packages/`. Theos does not support spaces in project paths; copy the checkout to a path without spaces before building if needed. The portable geography test can be run with `cc tests/geo_test.c Shared/Geo.c -lm -o /tmp/gpsnav-geo-test && /tmp/gpsnav-geo-test`.

MIT licensed; see [LICENSE](LICENSE).
