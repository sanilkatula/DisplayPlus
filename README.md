# Display+

Display+ is a macOS menu bar utility for managing external display modes.

## Features

- Detect connected displays
- Show HiDPI / LoDPI modes
- Switch available macOS display modes
- Install native HiDPI Retina Packs for external displays
- Show installed / needs restart state
- Built-in display brightness
- System volume control

## Warning

Display+ can install macOS display override files for external monitors. These changes may require a display reload or restart before macOS exposes the new HiDPI modes.

## Recovery

If an external monitor becomes unstable after installing a Retina Pack:

1. Disconnect the external monitor.
2. Boot using the built-in display.
3. Open Terminal and run:

```bash
sudo rm -rf /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-*
sudo rm -f /Library/Preferences/com.apple.windowserver.displays.plist
rm -f ~/Library/Preferences/ByHost/com.apple.windowserver*.plist
sudo reboot
```
