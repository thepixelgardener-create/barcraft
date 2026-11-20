<img src="assets/icon.svg" width="64" height="64" alt="">

# Barcraft

**The skinnable bar for Omarchy.**

Barcraft (`thepixelgardener.barcraft`) is Omarchy's own bar with a skin engine on top. It hosts every built-in and third-party `bar-widget`, popup, tooltip, drag-and-drop reordering and multi-monitor layout unchanged, and it follows the active theme live.

## Highlights

- **Omarchy standard switch.** One switch at the top of the Studio shows the bar exactly as Omarchy ships it: Omarchy's own size tokens, bar colors and Glassy setting, measured pixel-identical to `omarchy.bar`. Your skins, drafts and per-monitor choices stay; pick any skin to switch back. Unlike `omarchy bar use omarchy.bar`, the Barcraft pill and Studio stay on the bar, since Omarchy only loads a bar plugin's widget while that bar is active.
- **8 built-in skins.** Classic: `Floating`, `Islands`, `Frosted`, `Capsule`, `Editorial`. Wild Craft (illustrated art): `Barber Pole`, `Runeforge`, `Long Rocket`.
- **Barcraft Studio.** Click the Barcraft pill in the bar. Hover a skin (or move the keyboard cursor onto it) to preview it on the bar, click to keep it. Craft every field live, save skins, rename and delete them, copy a skin as TOML or paste one someone shared.
- **Keyboard first.** The Studio is a keyboard panel: arrows or `hjkl` move, `←`/`→` adjust, `Return`/`Space` activate, `1`/`2` switch tabs, `R` renames and `Del` deletes a saved skin, `Esc` closes, `Tab` moves to the next panel.
- **Per-monitor skins.** "Apply to" gives one screen its own skin. Height and icon color stay shared, since every widget draws with the one size and foreground the bar publishes.
- **Theme-native colors.** Theme swatches store live references (`theme.blue`) that follow theme switches; fixed colors store `#rrggbb`. Text and icons flip to a readable ink automatically (WCAG 4.5:1) unless you pick an icon color.
- **Omarchy-native settings.** Glass blur is Omarchy's own Glassy bar (`omarchy-bar background`), and icon size writes Omarchy's own `[bar]` icon tokens. Nothing is reimplemented beside the shell.
- **Nothing loops.** Every skin, Wild Craft art included, is still, so the bar never redraws on its own. Only Omarchy's short transitions remain (switching skins, auto-hide), and `omarchy toggle animations` turns those off too.

## Install

```bash
git clone <this repo> ~/Code/barcraft
ln -s ~/Code/barcraft ~/.config/omarchy/plugins/thepixelgardener.barcraft
omarchy-shell shell rescanPlugins
omarchy plugin enable thepixelgardener.barcraft
omarchy bar use thepixelgardener.barcraft
omarchy bar put thepixelgardener.barcraft --section right
```

## Keybindings and IPC

```bash
omarchy-shell shell toggle thepixelgardener.barcraft   # open/close the Studio
omarchy-shell barcraft reveal                          # peek an auto-hidden bar out
omarchy-shell barcraft toggleAutoHide
omarchy-shell barcraft next                            # next skin, prints its name
omarchy-shell barcraft setSkin islands
omarchy-shell barcraft followTheme
omarchy-shell barcraft toggleStandard                  # Omarchy's own bar look on/off
omarchy-shell barcraft setSkin standard                # the same, as a skin id
```

For example, in `~/.config/hypr/bindings.conf`:

```ini
bindd = SUPER ALT, B, Barcraft Studio, exec, omarchy-shell shell toggle thepixelgardener.barcraft
bindd = SUPER, B, Peek the bar, exec, omarchy-shell barcraft reveal
```

## Skins

A skin is a `[bar-skin]` section. Save one from the Studio to `~/.config/omarchy/bar-skins/<name>.toml`, or ship one with a theme in its `shell.toml`. `[bar-skin]` is Barcraft's own section; Omarchy's shell ignores it, so a theme carrying it stays valid without Barcraft.

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

# Geometry
height            = 30
edge-margin       = 6
side-margin       = 10
section-gap       = 10
inner-padding-x   = 10
radius            = 14
icon-scale        = 1.00             # 0.8 - 1.5, sets Omarchy's [bar] icon tokens

# Surface & border
background-alpha  = 0.88
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

Skins from earlier Barcraft versions load unchanged: `art = "warcraft"` becomes `runeforge`, and a lone `contrast` drives the surface too.

## Files Barcraft writes

- `~/.config/omarchy/barcraft.toml`: the Omarchy standard switch, the chosen skin, per-monitor skins (`[barcraft-monitors]`), preferences that hold for every skin (auto-hide delay and mode, peek on workspace switch), and an unsaved draft.
- `~/.config/omarchy/bar-skins/*.toml`: saved skins.
- `~/.config/omarchy/shell.toml`: only when a skin's icon size isn't 100%. Barcraft adds `[bar]` icon tokens marked `# barcraft`, never touches a token you set by hand, and removes its lines again at 100%.
- Blur runs `omarchy-bar background glassy|opaque`, the same switch as Omarchy's own menu. A clear bar you picked stays clear.

## Development

```bash
node tests/skinparser.test.js        # parser, TOML, state and shell.toml regression tests
omarchy plugin validate .
omarchy agent look plugin .
scripts/sync-upstream.sh --check     # has Omarchy's bar changed since the last sync?
scripts/sync-upstream.sh             # three-way merge Omarchy's bar into Bar.qml / BarModel.js
```

`Bar.qml` and `BarModel.js` are Omarchy's bar plugin with Barcraft's changes on top. `upstream/*.orig` records the Omarchy version they were last synced with (`upstream/VERSION`). After an Omarchy update, run the sync script, look at the bar, and commit. If it reports conflicts, resolve them and run `scripts/sync-upstream.sh --mark-synced`.

| File | Role |
| --- | --- |
| `SkinParser.js` | TOML subset, skin validation, built-in skins, state file, shell.toml icon tokens |
| `SkinEngine.qml` | State, saving, previews, per-monitor skins, blur sync, clipboard |
| `SkinLook.qml` | A skin's resolved colors and geometry (one per bar surface and thumbnail) |
| `Bar.qml` | Omarchy's bar with skinned surfaces, auto-hide, widget pills, IPC |
| `BarWidget.qml`, `StudioContent.qml` | The widget and the Studio keyboard panel |
| `SkinThumbnail.qml`, `ColorPickerField.qml`, `BarArtLayer.qml`, `BarBezelOverlay.qml` | Studio and art building blocks |
