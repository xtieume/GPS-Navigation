# GPSNav app — UI redesign

Native iOS look (Apple Maps style, HIG). UIKit only, SF Symbols for every icon, system colors (light + dark), no third-party deps.

## Layout
```
┌────────────────────────────────┐
│ [🔍 Search places        ] [⚙︎] │  floating, blurred capsule, below safe area
│                          ┌───┐ │
│                          │ ◎ │ │  right floating stack (blur, 44×44, radius 12)
│        MAP (full screen) │ ★ │ │   location.fill  = real current location
│                          └───┘ │   star           = bookmarks
│   (◉ 42 km/h pill when moving) │
├────────────────────────────────┤
│ ─── grabber                    │  bottom card: UIVisualEffectView,
│ [📍Fixed][〰Route][🔀Random]    │  top radius 20, shadow, respects home indicator
│ ● Spoofing · 10.77874,106.73835│  status dot green/grey + monospaced coords, tap=copy
│ <mode-specific row>            │
│ [ ▶︎  Start spoofing          ] │  primary filled button 50pt; becomes red "■ Stop"
│ ★ Saved   🗺 Routes  🕘 History │  secondary icon-over-label buttons
└────────────────────────────────┘
```

## Icons (SF Symbols)
- Search bar: magnifyingglass (system). Settings: gearshape.fill.
- My location: location.fill (location when not centered). Bookmarks: star.fill.
- Modes: mappin.and.ellipse (Fixed), point.topleft.down.curvedto.point.bottomright.up (Route), shuffle (Random).
- Start: play.fill / Stop: stop.fill. Save bookmark: bookmark.fill. Copy: doc.on.doc.
- Route: A = circle.fill green, B = mappin red; swap = arrow.up.arrow.down; loop = arrow.triangle.2.circlepath; speed = speedometer.
- Random: scope (radius), timer (interval).
- Secondary row: star.fill Saved, map.fill Routes, clock.arrow.circlepath History.

## Mode rows
- Fixed: hint "Long-press the map to pick a point" + bookmark.fill button "Save".
- Route: two chips "A: <name/coords>" / "B: ..." (tap chip then long-press map to set; or set from search result), swap button, speed menu button (UIMenu: Walk 5, Bike 20, 40, 60, 80, 120, Custom…) showing "speedometer 40 km/h", loop toggle as icon button (tinted when on), "Save route" button.
- Random: radius stepper/menu (100 m, 500 m, 1 km, 5 km), interval menu (10 s, 30 s, 1 min, 5 min); center = current selected point.

## Behaviour
- My-location button: request When-In-Use permission, get the REAL location (this app is excluded from the tweak), center map with animation, and set it as the selected point (like GPSFaker's My Location FAB). Map showsUserLocation = YES.
- Long-press map (0.4 s) drops point; haptic UIImpactFeedbackGenerator light. Start/Stop: notification haptic success.
- Markers: spoofed engine position = custom blue dot with white ring + heading arrow when moving; selected point = red pin; A green, B red; route polyline systemBlue width 5, rounded caps.
- Search: results list in a sheet (UISheetPresentationController medium/large); selecting a result centers map and sets point (or A/B in route mode). History shown when search field empty.
- Bookmarks/Routes/History/Settings: sheets with insetGrouped UITableView, swipe-to-delete, empty states with icon + text.
- Settings sheet: blacklist apps, About (version, GitHub link).
- Touch targets ≥ 44 pt, spacing 8/12/16 grid, labels use Dynamic Type (preferredFont), coordinates use monospacedDigitSystemFont, VoiceOver labels on icon-only buttons.
