# Display+

Display+ is a macOS menu bar utility for managing external displays, resolutions, HiDPI modes, refresh rates, brightness, and volume.

It is built for people who use external monitors with macOS and want sharper text, cleaner scaling options, and easier display control from the menu bar.

> Display+ is currently in beta. Native HiDPI mode installation modifies macOS display override files and should be tested carefully.

------------------------------------------------------------------------

## What Display+ Does

Display+ helps you inspect and control connected Mac displays from a simple menu bar interface.

Current features include:

-   Detect built-in and external displays
-   Show current resolution, framebuffer size, refresh rate, and HiDPI/LoDPI status
-   List available macOS display modes
-   Switch between available resolutions
-   Show HiDPI and LoDPI tags for every mode
-   Quick HiDPI on/off toggle when compatible modes are available
-   Generate and install native HiDPI Retina Packs for external displays
-   Show whether a Retina Pack is:
    -   Not installed
    -   Installed but needs restart/display reload
    -   Installed and available
    -   Partially loaded
-   Install custom HiDPI resolutions
-   Show installed HiDPI resolutions created by Display+
-   Control built-in display brightness
-   Control the current macOS default output volume
-   Run as a menu bar app
-   Quit from the menu bar icon

------------------------------------------------------------------------

## Why This Exists

macOS does not always expose HiDPI scaling options for third-party external monitors.

On Apple displays and some Apple-managed display paths, text looks crisp because macOS renders the desktop at a higher backing framebuffer and scales it down. On many third-party monitors, macOS only exposes standard LoDPI modes, which can make text look thin, blurry, or less sharp.

Display+ tries to improve this by exposing and managing HiDPI modes for external displays.

------------------------------------------------------------------------

## HiDPI vs LoDPI

A normal LoDPI mode might look like this:

``` text
Looks Like: 1728 × 1080
Framebuffer: 1728 × 1080
Mode: LoDPI
```

A HiDPI mode uses a larger framebuffer:

``` text
Looks Like: 1728 × 1080
Framebuffer: 3456 × 2160
Mode: HiDPI
```

The UI appears the same size, but macOS has more pixels to render text and interface elements, which can make the display look sharper.

## Important Limitation

Native HiDPI overrides are not universal for every monitor.

They are installed for a specific monitor identity:

``` text
DisplayVendorID-xxxx / DisplayProductID-yyyy
```

That means:

A Retina Pack applies to that monitor model on this Mac. It may also apply to another identical monitor model. It does not automatically apply to every possible future monitor. A new monitor model may need its own Retina Pack.

## Restart / Display Reload

After installing a native Retina Pack, macOS may not show the new HiDPI modes immediately.

Display+ will show a status such as:

``` text
Needs restart
```

That means the override file was installed, but macOS has not loaded the new modes yet.

After restart or display reload, Display+ can show:

``` text
Installed
```
