<img src="assets/icon.svg" width="64" height="64" alt="">

# Barcraft

**The skinnable bar for Omarchy.**

Barcraft (`thepixelgardener.barcraft`) is Omarchy's own bar with a skin engine on top. It hosts every built-in and third-party `bar-widget`, popup, tooltip, drag-and-drop reordering and multi-monitor layout unchanged, and it is built from Omarchy's own foundation: its settings live in `shell.json`, its presets follow the theme and Hyprland, and it shows up in Omarchy's menu, OSD and update hooks.

## Highlights

- **Omarchy standard.** The first tile in the Studio (click it again to leave) shows the bar exactly as Omarchy ships it, measured pixel-identical to `omarchy.bar`. Your skins stay; pick one to switch back. Unlike `omarchy bar use omarchy.bar`, the Barcraft pill and Studio stay on the bar, since Omarchy only loads a bar plugin's widget while that bar is active.
- **Presets built from Omarchy's tokens.** "Auto" geometry follows the foundation: the theme's bar size (`[bar] size-horizontal`), Omarchy's panel gap to the screen edge, Hyprland's `gaps_out` at the sides so the bar lines up with your windows, Hyprland's `decoration:rounding` for corners, and the theme's bar alpha. Change your Hyprland rounding or theme and the bar follows.
- **8 built-in skins.** Classic: `Floating`, `Islands`, `Frosted`, `Capsule`, `Editorial`. Wild Craft (illustrated, still art): `Barber Pole`, `Runeforge`, `Long Rocket`.
- **Barcraft Studio.** Click the Barcraft pill. Tabs: **Skins · Colors · Geometry · Surface · Behavior**. Hover a skin (or move the keyboard cursor onto it) to preview it on the bar, click to keep it. Edit every field live, save, rename and delete skins, copy one as TOML or paste one someone shared.
- **Keyboard first.** The Studio is an Omarchy keyboard panel: arrows or `hjkl` move, `←`/`→` adjust, `Return` toggles a slider's Auto, `1`–`5` pick a tab, `R` renames and `Del` deletes a saved skin, `Esc` closes, `Tab` moves to the next panel.
- **Per-monitor skins.** "Apply to" gives one screen its own skin. Height and icon color stay shared, since every widget draws with the one size and foreground the bar publishes.
- **Theme-native colors.** Theme swatches store live references (`theme.blue`) that follow theme switches. Text and icons flip to a readable ink automatically (WCAG 4.5:1) unless you pick an icon color.
- **Nothing loops.** Every skin is still, so the bar never redraws on its own; Omarchy's short transitions remain and follow `omarchy toggle animations`.

## How it fits Omarchy

| Omarchy foundation | Barcraft |
| --- | --- |
| Feature settings in `shell.json` subtrees, written by the host | `bar.barcraft`, beside `position`, `background` and `layout`; written through the shell (`mutateShellConfig`), so `omarchy bar reset` resets it too and `jq` reads it |
| The bar's user files in `~/.config/omarchy/bar/` | Saved skins in `~/.config/omarchy/bar/skins/` |
| Theme tokens in `shell.toml`, per-section overrides `shell.<section>.toml` | A theme ships its skin as `[bar-skin]` in `shell.toml`, or as its own `shell.bar-skin.toml` |
| `[bar]` icon tokens, `~/.config/omarchy/shell.toml` overrides | Icon size writes `[bar]` icon tokens there, marked `# barcraft`, never over yours |
| `omarchy-bar background` (Glassy, Hyprland blur) | Glass blur is that switch |
| Omarchy menu extensions | Optional Appearance → Menu Bar → Barcraft, with a ✓ by the skin you wear |
| OSD (`omarchy osd`) | Skin changes by keybinding, right-click or IPC show their name |
| `~/.config/omarchy/hooks/post-update.d/` | Optional check after Omarchy updates: a notification when Omarchy's bar moved under Barcraft |
| The Omarchy UI kit ([omacom/omarchy-ui](https://github.com/omacom/omarchy-ui)), the shell's own QML kit as a library | The Studio is drawn with it (`kit/`), so it looks and behaves like Omarchy Control: Tabs, SettingRow, ButtonGroup, ValueSlider, ToggleSwitch, SwatchStrip, ColorWell, CursorSurface, Keycaps |
| Keyboard panels, `Style.duration`, `Translations`, `PlainText` | The Studio uses them; English and German ship |

## Install

```bash
omarchy plugin add <this repo's git url> --enable
omarchy bar use thepixelgardener.barcraft
omarchy bar put thepixelgardener.barcraft --section right
```

From a local checkout instead: `ln -s "$PWD" ~/.config/omarchy/plugins/thepixelgardener.barcraft`, then `omarchy-shell shell rescanPlugins` and the two `omarchy bar` lines.

## Keybindings and IPC

In `~/.config/hypr/bindings.lua`, the way Omarchy binds its own panels:

```lua
o.bind("SUPER + ALT + B", "Barcraft Studio", { panel = "thepixelgardener.barcraft" })
o.bind("SUPER + B", "Peek the bar", { ipc = "barcraft.reveal" })
o.bind("SUPER + SHIFT + B", "Next bar skin", { ipc = "barcraft.next" })
```

```bash
omarchy-shell shell toggle thepixelgardener.barcraft   # open/close the Studio
omarchy-shell barcraft studio geometry                 # open it on a tab: presets, colors, geometry, surface, behavior
omarchy-shell barcraft reveal                          # peek an auto-hidden bar out
omarchy-shell barcraft next                            # next skin (OSD), prints its name
omarchy-shell barcraft setSkin islands                 # any skin id, "standard" or "theme"
omarchy-shell barcraft toggleStandard                  # Omarchy's own bar look on/off
omarchy-shell barcraft toggleAutoHide
omarchy-shell barcraft followTheme
omarchy-shell barcraft current                         # skin id, "standard", "theme" or "draft"
omarchy-shell barcraft doctor                          # a health report
```

## Skins

A skin is a `[bar-skin]` section. Save one from the Studio, or ship one with a theme. `[bar-skin]` is Barcraft's own section; Omarchy's shell ignores it, so a theme carrying it stays valid without Barcraft.

The short form picks a skin and overrides only what it names:

```toml
[bar-skin]
preset = "islands"
radius = 18
```

Every key:

```toml
[bar-skin]
name              = "Islands"
description       = "Separate floating pills for left, center, and right"
preset            = "islands"        # optional base: any built-in or saved skin id
mode              = "islands"        # edge | floating | islands
art               = "none"           # none | barber | runeforge | rocket
theme-tint        = false            # recolor art with the theme
bezel             = "none"           # none | raised | inset | ridge | glass
bezel-strength    = 0.75
contrast          = 1.00             # text & icon contrast, 0.5 - 1.5
surface-tone      = 1.00             # surface depth, 0.5 - 1.5
custom-background = "theme.dark_background"   # "#rrggbb" or theme.<colors.toml key>
custom-foreground = "#f2f5fa"        # icons & text; leave out for automatic contrast
custom-accent     = "theme.magenta"

# Geometry: a number, or "auto" to follow Omarchy and Hyprland
height            = "auto"           # theme's [bar] size-horizontal / size-vertical
edge-margin       = "auto"           # Omarchy's panel gap to the screen edge
side-margin       = "auto"           # Hyprland gaps_out: lines up with windows
radius            = "auto"           # Hyprland decoration:rounding
width             = 100              # percent of the screen, centered (floating, islands)
section-gap       = 10
inner-padding-x   = 10
icon-scale        = 1.00             # 0.8 - 1.5, sets Omarchy's [bar] icon tokens

# Surface & border
background-alpha  = "auto"           # 0 - 1, or the theme's [bar] background-alpha
fill              = "solid"          # solid | gradient
gradient-to       = "theme.blue"     # far end of a gradient; the accent if left out
blur              = true             # Omarchy's Glassy bar
border            = "subtle"         # none | subtle | accent | hyprland
border-alpha      = 0.24
border-width      = 1
shadow            = false
shadow-strength   = 0.5
widget-style      = "plain"          # plain | pills | chips

# Behavior
visibility        = "always"         # always | autohide
hover-edge-px     = 4
accent-hairline   = true
```

Skins from earlier Barcraft versions load unchanged: `art = "warcraft"` becomes `runeforge`, a lone `contrast` drives the surface too, and skins in the old `~/.config/omarchy/bar-skins/` folder still load.

## What Barcraft writes

- `~/.config/omarchy/shell.json` → `bar.barcraft`: Omarchy standard, the chosen skin, per-monitor skins, preferences that hold for every skin, and an unsaved draft. Barcraft 0.2's `~/.config/omarchy/barcraft.toml` moves here once and stays as `barcraft.toml.migrated`.
- `~/.config/omarchy/bar/skins/*.toml`: saved skins.
- `~/.config/omarchy/shell.toml`: only when a skin's icon size isn't 100%: `[bar]` icon tokens marked `# barcraft`, removed again at 100%.
- Only when switched on in the Studio's Omarchy section: a block between `// barcraft:begin` and `// barcraft:end` in `~/.config/omarchy/extensions/omarchy-menu.jsonc`, and `~/.config/omarchy/hooks/post-update.d/barcraft-sync`. Switching off removes them.
- Glass blur runs `omarchy-bar background glassy|opaque`, the same switch as Omarchy's menu. A clear bar you picked stays clear.

## Development

```bash
node tests/skinparser.test.js        # parser, TOML, shell.json state, menu block, icon tokens
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
omarchy plugin validate .
omarchy agent look plugin .
scripts/sync-upstream.sh --check     # has Omarchy's bar changed since the last sync?
scripts/sync-upstream.sh             # three-way merge Omarchy's bar into Bar.qml / BarModel.js
```

The Studio is drawn with the Omarchy UI kit, vendored into `kit/` at a pinned revision (`kit/KIT_REV`, the same one thepixelgardener.omarchyform uses). `KitTheme.qml` feeds the kit the theme the shell draws with, through the QML stand-in `kit/Theme/ThemeSource.qml`, since a shell plugin can load none of the kit's C++. To take a newer kit: `node tools/vendor-kit.js /path/to/omarchy-ui` (`--check` says what would change). Text is typed through `LineField.qml`, never a TextInput: Qt 6.12.0's TextInput reads the whole clipboard on every clipboard change, which inside the shell could stall it.

`Bar.qml` and `BarModel.js` are Omarchy's bar plugin with Barcraft's changes on top. `upstream/*.orig` records the Omarchy version they were last synced with (`upstream/VERSION`). After an Omarchy update, run the sync script, look at the bar, and commit. If it reports conflicts, resolve them and run `scripts/sync-upstream.sh --mark-synced`.

The widget finds the bar's engine by walking up to the bar strip it sits in (`barcraftEngine`). Don't replace that with a shared `.pragma library`: Omarchy loads `Bar.qml` and the widget under different URLs, so each would get its own copy.

| File | Role |
| --- | --- |
| `SkinParser.js` | TOML subset, skin validation, built-in skins, shell.json state, menu block, shell.toml icon tokens |
| `SkinEngine.qml` | State, saving, previews, per-monitor skins, blur sync, clipboard, Omarchy integration, doctor |
| `SkinLook.qml` | A skin's resolved colors and geometry, "auto" included (one per bar surface and thumbnail) |
| `Bar.qml` | Omarchy's bar with skinned surfaces, auto-hide, widget pills, IPC |
| `BarWidget.qml`, `StudioContent.qml` | The widget and the Studio keyboard panel |
| `BarcraftMark.qml`, `SkinThumbnail.qml`, `ColorPickerField.qml`, `BarArtLayer.qml`, `BarBezelOverlay.qml` | Building blocks |
| `kit/`, `KitTheme.qml`, `LineField.qml`, `tools/vendor-kit.js` | The Omarchy UI kit, its theme bridge, the safe text field, and the vendoring script |
