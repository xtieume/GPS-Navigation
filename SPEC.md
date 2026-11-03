# GPSNav — iOS jailbreak GPS spoofer (spec)

iOS port of the Android app at /Users/macbook/Desktop/projects/GPSFaker (read its README + docs/plans for feature reference only).
Target: jailbroken iOS 16.0+ arm64/arm64e. Primary: **rootless** (Dopamine, palera1n rootless). Also build **rootful** (palera1n rootful). Theos-based.

## Features (parity with GPSFaker)
1. Fake location — long-press/tap on map sets the spoofed coordinate; global ON/OFF switch.
2. Route simulation — pick A and B, route along real roads (MKDirections, automobile/walking), choose speed (km/h presets 5/20/40/60/80/120 + custom), simulate movement with realistic course/speed fields.
3. Reverse loop — at destination, go back B→A→B... (toggle).
4. Random mode — jump to random point within radius R (m) around a center every N seconds.
5. Search — MKLocalSearch with search history (last 20).
6. Bookmarks & saved routes — save/list/delete/apply.
7. Per-app: optional blacklist of bundle IDs that should see real location (simple list in app settings). Keep simple.

## Architecture
Three Theos subprojects in one repo (aggregate Makefile):

- `Tweak/` — `GPSNav.dylib`, Logos (`Tweak.x`), filter `com.apple.CoreLocation` bundle (inject into apps + SpringBoard; exclude daemons that crash).
  - In apps: hook `CLLocationManager` — `-location`, `-setDelegate:` / delegate `locationManager:didUpdateLocations:` (wrap delivered locations), `startUpdatingLocation`, `requestLocation`, `-heading` untouched. When spoof enabled, deliver a fake `CLLocation` (coordinate, altitude, horizontalAccuracy 5, course, speed, timestamp now) to delegate on a 1s timer while updating is active. Also hook `CLLocation` consumers only via the manager (don't hook CLLocation globally).
  - Reading current spoof state in sandboxed apps: **Darwin notify state** (works across sandbox, no deps): names `com.xtieume.gpsnav.lat`, `.lon`, `.flags` (uint64; lat/lon stored as raw double bits via memcpy; flags bit0=enabled, plus speed/course packed in `.motion` = two float32 bits). Change notification `com.xtieume.gpsnav.changed`. Tweak registers with `notify_register_check` and calls `notify_get_state` (cheap) on each use.
  - In SpringBoard: the **engine**. Reads config plist `/var/mobile/Library/Preferences/com.xtieume.gpsnav.plist` (CFPreferences / NSDictionary file) on `com.xtieume.gpsnav.reload` notification and at boot; runs static / route / random modes on an NSTimer (1s tick), publishes position via notify_set_state + posts `changed`. Route polyline is stored in the plist as an array of [lat,lon]. Engine persists "current position" back so state survives respring. SpringBoard is always alive, so simulation continues while the app is backgrounded.
  - Blacklist: tweak checks `NSBundle.mainBundle.bundleIdentifier` against list; list is read once from plist where readable, plus also published as notify-friendly: simplest is the app writes blacklist into plist and SpringBoard can't push lists via notify — so for sandboxed apps use a hash: engine publishes nothing; instead tweak tries reading plist (may fail in sandbox → treat as not blacklisted). Acceptable limitation, document it.
- `App/` — companion app `GPSNav.app` (Objective-C, UIKit + MapKit, no third-party deps), installed to `/Applications` (rootless: `/var/jb/Applications`). Needs entitlements to write `/var/mobile/Library/Preferences/com.xtieume.gpsnav.plist` (app is unsandboxed via `com.apple.private.security.no-container` + `platform-application`; ldid-sign with entitlements). Single map screen + bottom controls: mode segmented (Fixed / Route / Random), ON/OFF switch, search bar, bookmark & routes sheets, speed picker, loop toggle, random radius/interval, blacklist screen, About. After writing plist → `notify_post("com.xtieume.gpsnav.reload")`. Shows engine's current position marker (read via notify_get_state, poll 1s).
- `layout/` + `control` — package `com.xtieume.gpsnav`, Name GPSNav, Depends `mobilesubstrate (>= 0.9.5000), firmware (>= 16.0)`, Architecture via THEOS_PACKAGE_SCHEME (rootless → iphoneos-arm64, rootful → iphoneos-arm). postinst: `uicache -p` the app path (rootless path aware); prerm/postrm unregister.

## Build
- Theos. `make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless` and rootful. `ARCHS = arm64 arm64e`, `TARGET = iphone:clang:latest:16.0`.
- GitHub Actions `.github/workflows/build.yml` on macos-latest: install Theos (clone theos/theos --recursive, ldid, use Xcode SDK), build both schemes, upload `.deb` artifacts; on tag `v*` create release with both debs.
- Local verification: install Theos at `~/theos` if missing (`git clone --recursive https://github.com/theos/theos.git ~/theos`; SDK from Xcode is fine via `SYSROOT` or theos sdks repo `theos/sdks` iPhoneOS16.x). `brew install ldid make dpkg` if needed. Build both debs locally; they must compile cleanly.

## Repo hygiene
- `.gitignore` (.theos, packages, .DS_Store).
- `README.md` English + `README.vi.md` Vietnamese: features, install (add deb via Sileo/Filza), usage, limitations, build.
- License MIT. Author "Tieu Me".
- No AI attribution anywhere. Do not commit or push.
