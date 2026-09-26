<p align="center"><img src="icon.png" width="128" alt="Show Desktop icon"></p>

# Show Desktop

A Dock button for macOS that instantly clears all windows away and shows the desktop — like *Show desktop* on Windows. Click once to hide everything, click again to bring it all back.

macOS has *Show Desktop* (F11 / Mission Control gesture / hot corner), but it only slides windows to the screen edges, and there is no one-click Dock button for it. This small single-file Swift utility adds one.

## Features

- **One click hides, the next click restores.** Strict alternation — no guessing based on what's on screen.
- **Instant.** Apps are hidden (like ⌘H) rather than minimized, so there is no Genie animation, no matter how many windows are open.
- **No flicker.** Screen updates are frozen while apps hide/unhide, and the result appears in a single frame.
- **Restores focus.** After restoring, the app that was active before goes back to the front, and the stacking order is preserved.
- **Leaves your state alone.** Apps that were already hidden before the click stay hidden.
- **Global hotkey** ⌃⌥D (works while the app is running).
- **No permissions required** — no Accessibility, no Screen Recording.
- Single Swift file, no Xcode project, no dependencies.

## Requirements

- macOS 12 or later
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/hamet/showdesktop.git
cd showdesktop
./build.sh      # compiles "Show Desktop.app" (swiftc + sips/iconutil for the icon)
./install.sh    # copies it to /Applications and adds it to the Dock
```

Then just click the icon in the Dock.

To have the ⌃⌥D hotkey available right after login, add *Show Desktop* in **System Settings → General → Login Items**. When launched at login it does nothing until you click or press the hotkey.

## How it works

- **Hide:** lists on-screen windows via `CGWindowListCopyWindowInfo`, takes every regular app that owns a visible window, and calls `NSRunningApplication.hide()` on each. Show Desktop activates itself *before* hiding: if the active app were hidden first, macOS would hand focus to the next app (usually Finder), and activating a hidden app unhides it.
- **Restore:** calls `unhide()` on exactly the apps it hid (back to front, to keep the stacking order) and re-activates the previously active app.
- **No flicker:** `SLSDisableUpdate` / `SLSReenableUpdate` from the private SkyLight framework (the same approach [yabai](https://github.com/koekeishiya/yabai) uses) freeze the screen until all apps have complied, capped at ~0.4 s. The system automatically re-enables updates after about a second, so the screen can never get stuck. If the symbols are ever removed from macOS, the app keeps working, just without the freeze.
- **Dock clicks:** a click can arrive as an activation, a reopen event, or both; events within 0.5 s of the last toggle are treated as the same click.

## Notes

- Windows are *hidden*, not minimized to the Dock. To bring back a single app, click its Dock icon or use ⌘Tab; the next click on Show Desktop restores the rest.
- Clicking the wallpaper or a desktop icon activates Finder, which brings back Finder's windows (this is how app hiding works on macOS).
- **Using a "click the active app's Dock icon to hide it" utility** (e.g. [dockhide](https://github.com/hamet/dockhide))? Exclude Show Desktop (`com.hamet.showdesktop`) there. Otherwise that utility intercepts the click on the active Show Desktop icon, hides Show Desktop itself, and macOS hands focus to Finder.
- To change the hotkey, edit `registerHotKey()` in `ShowDesktop.swift` (`kVK_ANSI_D`, `controlKey | optionKey`).
- The app is ad-hoc signed. If macOS refuses to open it after downloading a prebuilt copy, build it yourself with `./build.sh`.

## Uninstall

```bash
pkill -x ShowDesktop
rm -rf "/Applications/Show Desktop.app"
```

Then drag the icon out of the Dock.

## License

[MIT](LICENSE)
