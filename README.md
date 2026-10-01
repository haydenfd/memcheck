# Memcheck

Memcheck lives in your Mac’s menu bar, checks memory every three seconds, and starts when you log in. The chip shows green for healthy memory, orange for a warning, and red for critical pressure. Click it to see what the health state means, available memory, and the five apps using the most memory right now.

## Build and run

On macOS 14 or later with Xcode installed, open `Package.swift` in Xcode or run:

```sh
swift test
sh scripts/install-app.sh
open "$HOME/Applications/Memcheck.app"
```

macOS may ask you to allow notifications or approve Memcheck in Login Items. If you previously denied notifications, enable them in System Settings → Notifications.

## Memory health

Memcheck follows the Mac’s memory pressure and fresh swap use. A high RAM percentage alone is not a warning because macOS uses spare RAM for cache. Warnings need 20 seconds of elevated pressure; critical pressure shows immediately. Recovery takes 30 seconds. Alerts repeat only after memory returns to normal.

App amounts combine each app's processes, including helpers such as browser renderers. They use macOS physical footprint, so they may differ from Activity Monitor's figures. System processes outside apps are not listed.

The menu's Health percentage is available memory divided by total RAM. The menu-bar color follows macOS memory pressure, so a lower percentage can still be green when memory is reclaimable.

App code is in `Sources/Memcheck`, tests are in `Tests/MemcheckTests`, and build scripts are in `scripts`.
