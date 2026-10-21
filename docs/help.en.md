# WatchLock Help

WatchLock is a macOS menu-bar app. Walk away wearing your Apple Watch and the Mac locks; come back and the screen wakes. Unlocking is done by macOS's built-in "Unlock with Apple Watch".

## 1. First run

1. Open the app. A menu-bar icon appears; follow the onboarding.
2. Grant **Bluetooth** (required). The default lock method also needs **Accessibility**. To avoid that, choose "System interface (no permission)" or "Display off only" under Settings > General > Lock method.
3. Pick and bind your Apple Watch in Settings > Device. **Automatic locking does nothing until a watch is bound**; the menu bar tells you so.
4. Turn on "Unlock with Apple Watch" in macOS System Settings. Otherwise the screen only wakes and you type your password.
5. (Recommended) Settings > Calibration > Distance calibration wizard: stay in your usual seat for 10 seconds to generate thresholds that fit your room.

## 2. Menu bar

| Icon state | Meaning |
| --- | --- |
| Near | Strong watch signal; stays unlocked |
| Away | Watch has been away for the configured time; locked or about to lock |
| Searching | Looking for the watch signal |
| Paused | You paused monitoring temporarily |
| Off | Monitoring is off |

The panel lets you lock now, pause, see the live signal against the thresholds, and tap "Was that a false lock?" to report one.

## 3. Settings

- **General**: lock method, away duration, launch at login, notifications, and two optional exceptions (both off by default):
  - Defer lock during meetings / presentations: when an app is preventing display sleep, locking is postponed and made up afterwards, with a hard upper limit.
  - Re-arm after manual unlock: if you unlock with your password while the watch is still far, lock again after the keyboard and mouse have been idle for a while.
- **Device**: bind or unbind the watch; optionally pick up to 3 "auxiliary devices" (iPhone, AirPods, …): if the watch merely stops advertising while a device you chose is still nearby, locking is held off. Auxiliary devices **only postpone** locks caused by "signal lost" (for at most 2 minutes); they never lock the Mac by themselves and cannot override a clearly weak watch signal. An iPhone may stop advertising once its screen is off, so results depend on the device's state.
- **Places**: save the current network as a "trusted place" (home, office); auto-lock pauses while you are connected to it and resumes when you leave. The menu bar shows a notice, and Resume re-enables locking for the current stay. Networks are recognized by their gateway and need no permission; the Wi-Fi name needs Location permission and is optional. Other devices on the same network can spoof the fingerprint, so this is a convenience feature, not a security boundary.
- **Calibration**: the wizard; adjust the "near" and "away" thresholds.
- **Diagnostics**: false-lock stats and auto tuning, diagnostic log.
- **About**: version, rerun onboarding, check for updates, open this manual.

## 4. FAQ

**The watch is right next to the Mac but it locked. Why?**
Look at the live signal in the menu bar. With the watch close it is about -42 dBm, and the default "away" threshold of -70 dBm is usually enough. If it still misfires, run the calibration wizard, or mark the lock as a false lock so the app relaxes the threshold.

**I walked away and nothing locked.**
Check, in order: a watch is bound; Bluetooth is granted; with the Control-Command-Q lock method, Accessibility is granted (you get a notification if not); the meeting deferral is not on while some app is blocking display sleep; monitoring is not paused. The log under Settings > Diagnostics states why each lock did or did not happen.

**It wakes the screen but does not unlock.**
Unlocking is macOS, not this app. Make sure "Unlock with Apple Watch" is on in System Settings, and the watch is unlocked and on your wrist.

**Do I have to re-authorize after updating?**
The app is not Developer ID signed or notarized, so replacing it may make macOS ask again for Bluetooth or Accessibility. Tick them again when prompted.

**Does it use the network?**
No, except when you click About > Check for Updates. That sends one request to GitHub to read the latest version number. It carries no information about your Mac, and nothing is downloaded or installed automatically.

## 5. Updating

Click "Check for Updates" in Settings > About. If a newer version exists, "Download" opens the GitHub Releases page. Download the DMG and drag the app into Applications to replace the old one.

## 6. Reporting problems

Open an issue at [GitHub Issues](https://github.com/MaelWeb/WatchLock/issues) and attach the log exported from Settings > Diagnostics (it is redacted).
