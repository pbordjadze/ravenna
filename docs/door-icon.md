# The icon through the door

A proposal for Paint by Moonlight (issue #15, part of the secret door, #5). Nothing here is built in
paint-by-number: its own sessions make it, through their own review, if Paul wants it.

Paul, October 28: "can we make it so switching from Paint by Moonlight to (whatever we call this mode
when we ship it for real)—switches the icon? In that case, we need to build a better icon."

The mode's name is Paul's to choose. Below it is **⟨the mode⟩**, and its icon set
`AppIcon-⟨Mode⟩`.

## What the painter sees

While ⟨the mode⟩ is on, the home screen shows Ravenna's icon in place of Paint by Moonlight's (the
same app, the same name under it). When the painter leaves the mode, Paint by Moonlight's icon comes
back. The candidates for the icon are on the page linked from #15; Paul picks one.

## How

iOS lets an app change its own home-screen icon to one of a few sets it ships:
`UIApplication.setAlternateIconName(_:)`. Ravenna's Settings › Icon already works this way.

1. **The asset.** The chosen icon's set goes into Paint by Moonlight's asset catalog as
   `AppIcon-⟨Mode⟩.appiconset`: three 1024 px PNGs (light, dark and tinted, as its own `AppIcon` has
   them) and their `Contents.json`, copied from Ravenna's catalog
   (`App/Ravenna/Resources/Assets.xcassets/AppIcon-<Name>.appiconset`, drawn by
   `sketchbook/icon_candidates.py`). About 1 MB. If the mode's settings show the icon, its 180 px
   picture (`Icon-<Name>.imageset`) goes too.
2. **The build setting.** Both configurations of the app target name it as an alternate:
   `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = AppIcon-⟨Mode⟩`. Without it, the compiled
   catalog leaves the set out and the switch fails.
3. **The switch.** A few lines, called when the mode opens or closes and when the app becomes
   active (the mode may have changed while it was away, if a clock opens it):

   ```swift
   import UIKit

   /// The home-screen icon follows ⟨the mode⟩, once the painter has chosen that it should.
   @MainActor enum ModeIcon {
       static let alternate = "AppIcon-⟨Mode⟩"

       /// Shows the mode's icon while it is on and Paint by Moonlight's otherwise. iOS changes an
       /// icon only for an app in the foreground, and shows its own alert each time.
       static func follow(modeIsOn: Bool) async {
           let app = UIApplication.shared
           guard app.supportsAlternateIcons, app.applicationState == .active else { return }
           let wanted = modeIsOn ? alternate : nil
           guard app.alternateIconName != wanted else { return }
           do { try await app.setAlternateIconName(wanted) } catch { Log.library.error("Icon: \(error)") }   // or a category of its own
       }
   }
   ```

   ```swift
   // Where the mode opens and closes, and on scenePhase becoming .active:
   if Preferences.iconFollowsMode { Task { await ModeIcon.follow(modeIsOn: mode.isOn) } }
   ```

## The limit: iOS's alert

Every call to `setAlternateIconName` that changes the icon shows iOS's own alert, "You have changed
the icon for “Paint by Moonlight”", with an OK button. An app can't turn it off. The ways around it
that circulate (calling the private `_setAlternateIconName:completionHandler:`, or presenting and
dismissing a view controller to swallow the alert) use private API or rely on undocumented
behaviour; App Review rejects private API (guideline 2.5.1), and Paint by Moonlight ships through the
App Store. So the alert stays, and the design has to make it welcome rather than a surprise. Other
limits:

- It works only while the app is in the foreground. A change made while the app is away waits for the
  next time it becomes active.
- The choice persists: the icon stays changed after the app is quit, until the app changes it back.
  If the mode can be lost (a clock set forward, a reinstall of its data), the app should put Paint
  by Moonlight's icon back the next time it is active.
- The alert names the app and shows the new icon on screen: on a shared screen it gives the secret
  away. Another reason to switch only when the painter asks.

## When to switch: options

1. **Follow the mode, once asked (recommended).** The first time the painter goes through the door,
   the mode offers it in one line: "Wear ⟨the mode⟩'s icon on the Home Screen while you're here?"
   with Not Now. Yes switches at once (the alert follows a tap, so it reads as the answer). From then
   on the icon follows the mode in and out, each time with the alert, which the painter has now seen
   and expects. A switch in the mode's settings turns following off, and turning it off puts Paint by
   Moonlight's icon back.
2. **Only on request.** No automatic switching: the mode's settings have the icon as a choice (as
   Ravenna's Settings › Icon does now), and leaving the mode puts Paint by Moonlight's icon back
   only if the painter asks. Quietest, and the furthest from what Paul asked for.
3. **Always.** The icon switches on every entry and exit with no question. Closest to the ask, but
   the alert then arrives unasked every time, and it shows the secret on screen. Not recommended.

Paul's call. Option 1 keeps "switching modes switches the icon" while every alert follows something
the painter chose.

## What goes from Ravenna

- The chosen `AppIcon-<Name>.appiconset` (light, dark, tinted) and, if shown, `Icon-<Name>.imageset`.
- `sketchbook/icon_candidates.py`, if the icon is ever redrawn: it lays the six candidates with
  andamento and is deterministic, so the set can be drawn again identically.
- No code: `ModeIcon` above is the whole of it, written in Paint by Moonlight's own style there.
