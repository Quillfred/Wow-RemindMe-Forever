# RemindMe Forever

A WoW Classic addon that pops up an icon on screen when something needs your attention.
Icons are display-only (not clickable), so they never block clicks and work fine in combat.

Supported clients: Classic (interface 16001, 16000, 11508, 11507). Not for Retail.

## Install
Copy the `RemindMeForever` folder into `World of Warcraft/_classic_era_/Interface/AddOns/`.

## Alerts
| Alert | Shows when | Settings |
|---|---|---|
| Voidwalker Sacrifice (Warlock) | Your Voidwalker knows Sacrifice and is at 5% HP or less. Uses the pet bar icon and shows its keybinding | `/rmf sacrifice <1-99>`, `/rmf sacrifice on/off` |

## Options
Click the minimap button (pocket watch) or type `/rmf` to open the options window:
test mode, unlock/move, minimap button, icon size (or match Cooldown Manager),
reset, and each alert's settings. It is also listed under the game's AddOns options.

Minimap button: left-click = options, right-click = test mode on/off, drag = move.

## Commands (`/rmf` or `/remindme`)
- no command: open the options window
- `unlock` / `lock`: move the icon position
- `test [on|off]`: show every alert icon until turned off
- `size match`: same size as your Cooldown Manager icons (default)
- `size <16-200>`: fixed icon size instead
- `minimap on|off`: show or hide the minimap button
- `reset`: reset position and size
- `list`: list alerts and their settings
- `sacrifice <1-99> | on | off`: Voidwalker HP % that shows Sacrifice

## Adding alerts
Each alert is one `ns.RegisterAlert({...})` entry in `RemindMeForever/Alerts.lua`, with a
`check(settings)` function that returns `true, "label"` when its icon should show.
