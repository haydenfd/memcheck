# Memcheck

Memcheck lives in your Mac’s menu bar, checks memory every three seconds, and starts when you log in. The chip shows green for healthy memory, orange for a warning, and red for critical pressure. Click it for a quick look at RAM, available memory, compression, wired memory, and swap.

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

The displayed **used** amount is total RAM minus free and reclaimable memory (inactive and speculative pages). Compressed and wired memory are included in used, so the number may differ from Activity Monitor.

App code is in `Sources/Memcheck`, tests are in `Tests/MemcheckTests`, and build scripts are in `scripts`.
