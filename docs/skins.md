# Making Barcraft Skins

A Barcraft skin is a single `[bar-skin]` TOML block. Every skin is still (no looping animations), safe to share as plain text, and automatically validated on load.

---

## 1. Craft a skin in Barcraft Studio

The fastest way to build a skin is visually:

1. Click the Barcraft pill on your bar (or run `omarchy-shell shell toggle thepixelgardener.barcraft`).
2. Pick a starting preset in **Skins** (hover or move the keyboard cursor to preview live).
3. Tune **Colors**, **Geometry**, **Surface**, and **Behavior** live on your bar.
4. Enter a name in the Studio footer and press **Save**.
   Barcraft writes `~/.config/omarchy/bar/skins/<slug>.toml` and lists it under **Your skins**.
5. Use **Copy TOML** to share a skin, or **Paste skin** to try one from your clipboard.

---

## 2. Write a standalone TOML skin file

Drop any `.toml` file into `~/.config/omarchy/bar/skins/` (reloads automatically).

### Shorthand (extend a built-in preset)

Set `preset` to any built-in (`floating`, `islands`, `frosted`, `capsule`, `editorial`, `matrix`, `runeforge`, `amiga`, `statusline`) or saved skin ID and override only the keys you want to change:

```toml
[bar-skin]
name        = "Dev Accent"
description = "Compact statusline with a Hyprland border"
preset      = "statusline"
border      = "accent"
border-alpha = 0.55
```

### Theme-native vs fixed colors

Color fields (`custom-background`, `custom-foreground`, `custom-accent`, `gradient-to`) accept either:

- **Theme tokens** (`theme.<colors.toml key>`, e.g. `theme.dark_background`, `theme.blue`, `theme.accent`, `theme.foreground`) — live references that automatically update when you switch Omarchy themes.
- **Fixed hex colors** (`"#rrggbb"`).

Leave `custom-foreground` unset and Barcraft automatically chooses a readable dark or light ink (WCAG 4.5:1) whenever a custom surface or gradient would reduce contrast.

### `"auto"` geometry & alpha

Setting `height`, `edge-margin`, `side-margin`, `radius`, or `background-alpha` to `"auto"` keeps your skin synchronized with Omarchy and Hyprland:

| Key | `"auto"` follows |
| --- | --- |
| `height` | Active theme's `[bar] size-horizontal` / `size-vertical` |
| `edge-margin` | Omarchy's panel gap to the screen edge |
| `side-margin` | Hyprland `gaps_out` so the bar lines up with tiled windows |
| `radius` | Hyprland `decoration:rounding` |
| `background-alpha` | Active theme's `[bar] background-alpha` |

---

## 3. Ship a skin inside an Omarchy theme

Theme authors can bundle a matching bar skin without breaking users who do not have Barcraft installed:

- Add a `[bar-skin]` section directly inside your theme's `shell.toml`, **or**
- Place it in its own `shell.bar-skin.toml` beside `shell.toml`.

Omarchy's shell ignores `[bar-skin]` when Barcraft is absent. When Barcraft is active and **Follow theme skin** is enabled, switching to your theme activates your bar skin automatically.

Example in a theme's `shell.bar-skin.toml`:

```toml
[bar-skin]
name        = "Nord Islands"
preset      = "islands"
radius      = "auto"
border      = "subtle"
border-alpha = 0.25
```

---

## Complete `[bar-skin]` TOML reference

```toml
[bar-skin]
format            = 1                # skin schema version (current: 1)
name              = "Islands"
description       = "Separate floating pills for left, center, and right"
preset            = "islands"        # optional base: any built-in or saved skin id
mode              = "islands"        # edge | floating | islands
art               = "none"           # none | matrix | runeforge | amiga
theme-tint        = false            # recolor Wild Craft art with the active theme
bezel             = "none"           # none | raised | inset | ridge | glass
bezel-strength    = 0.75             # 0.15 - 1.00
contrast          = 1.00             # text & icon contrast, 0.50 - 1.50
surface-tone      = 1.00             # surface depth, 0.50 - 1.50
custom-background = "theme.dark_background"   # "#rrggbb" or theme.<colors.toml key>
custom-foreground = "#f2f5fa"        # icons & text; omit for automatic WCAG 4.5:1 ink
custom-accent     = "theme.magenta"

# Geometry: a number, or "auto" to follow Omarchy and Hyprland
height            = "auto"           # 22 - 56, or "auto"
edge-margin       = "auto"           # 0 - 24, or "auto"
side-margin       = "auto"           # 0 - 48, or "auto"
radius            = "auto"           # 0 - 28, or "auto"
width             = 100              # 30 - 100 (% of screen width, centered; floating & islands)
section-gap       = 10               # 0 - 32
inner-padding-x   = 10               # 4 - 24
icon-scale        = 1.00             # 0.80 - 1.50, scales Omarchy's [bar] icon tokens

# Surface & border
background-alpha  = "auto"           # 0.00 - 1.00, or "auto"
fill              = "solid"          # solid | gradient
gradient-to       = "theme.blue"     # far end of gradient; defaults to accent
blur              = true             # syncs Omarchy's Glassy bar (Hyprland blur)
border            = "subtle"         # none | subtle | accent | hyprland
border-alpha      = 0.24             # 0.00 - 1.00
border-width      = 1                # 0 - 4
shadow            = false
shadow-strength   = 0.50             # 0.10 - 1.00
widget-style      = "plain"          # plain | pills | chips

# Behavior
visibility        = "always"         # always | autohide
hover-edge-px     = 4                # 1 - 16
accent-hairline   = true
```

### Backwards & forward compatibility

- Skins from earlier Barcraft versions (including exports without a `format` line) load unchanged: `art = "warcraft"` maps to `runeforge`, a single `contrast` value also drives `surface-tone`, and files in `~/.config/omarchy/bar-skins/` are still discovered alongside `~/.config/omarchy/bar/skins/`.
- **Paste skin** is strict for `format = 1` (and unversioned skins): any syntax error, unknown key, invalid value, or unresolved `preset` rejects the paste and leaves the current draft and undo history intact. Out-of-range numbers clamp and report the adjustment.
- If you paste a skin whose `format` is higher than your Barcraft version supports (e.g. `format = 2`), Barcraft applies the fields it understands, lists the keys it skipped, and keeps **Undo paste**. Skins on disk and in themes stay tolerant and report diagnostics via `omarchy-shell barcraft doctor`.

---

## Contributing new built-in presets or Wild Craft art

Want to add a preset or custom still artwork to Barcraft itself?

1. **Preset only**: add a `preset({ ... })` entry to `builtinSkins()` in [`SkinParser.js`](../SkinParser.js), add localized descriptions to [`i18n/en.json`](../i18n/en.json) and [`i18n/de.json`](../i18n/de.json), and add a test in [`tests/skinparser.test.js`](../tests/skinparser.test.js).
2. **Custom artwork (`art = "<id>"`)**:
   - Register the art ID in `VALID_ARTS` in [`SkinParser.js`](../SkinParser.js).
   - Add a static QML `Canvas` in [`BarArtLayer.qml`](../BarArtLayer.qml) that paints once on resize/theme/contrast change (zero timers, zero per-frame redraws) and respects `themeTint`.
   - Expose the option in the **Craft Art** row of [`StudioContent.qml`](../StudioContent.qml) and add its `art.<id>` label in `i18n/*.json`.
3. Run the test suite (`node tests/skinparser.test.js` and `omarchy plugin validate .`) before opening a PR.
