# Memcheck

Memcheck lives in your Mac’s menu bar, checks memory every three seconds, and starts when you log in. The chip shows green, orange, or red for macOS memory pressure. Click it to see estimated available memory, swap used, and the five apps using the most memory right now. App actions include Quit and Force Quit; these are disabled for system apps.

## Build and run

On macOS 14 or later with Xcode installed, open `Package.swift` in Xcode or run:

```sh
swift test
sh scripts/install-app.sh
open "$HOME/Applications/Memcheck.app"
```

macOS may ask you to allow notifications or approve Memcheck in Login Items. If you previously denied notifications, enable them in System Settings → Notifications.

## Memory health

Memcheck displays macOS memory pressure directly. Available RAM and swap used are separate readings, not health scores. With notifications allowed in macOS, warning and critical pressure send native banners immediately; after 30 seconds of normal pressure, a recovery banner confirms things are good again. Alerts repeat only after memory returns to normal.

App amounts combine each app's processes, including helpers such as browser renderers. They use macOS physical footprint, so they may differ from Activity Monitor's figures. System processes outside apps are not listed.
While the menu is open, each app shows its memory change since the first reading in that menu session.

The menu's available RAM estimate includes free, inactive, and speculative memory. It may differ from Activity Monitor's memory figures. Force Quit asks for confirmation because unsaved changes may be lost.

App code is in `Sources/Memcheck`, tests are in `Tests/MemcheckTests`, and build scripts are in `scripts`.
