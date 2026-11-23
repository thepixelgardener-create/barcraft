# Reference & Development

## Studio keyboard shortcuts

Barcraft Studio is an Omarchy keyboard panel:

- **Arrows** or `hjkl` — move cursor
- `←` / `→` — adjust slider or option
- `Return` / `Space` — pick skin, activate control, or toggle a slider's **Auto**
- `1`–`5` — jump to **Skins · Colors · Geometry · Surface · Behavior**
- `R` / `Del` — rename or delete a saved skin
- `Esc` — close panel
- `Tab` — move to the next bar panel

---

## Keybindings & IPC

In `~/.config/hypr/bindings.lua`, the same way Omarchy binds its own panels:

```lua
o.bind("SUPER + ALT + B", "Barcraft Studio", { panel = "thepixelgardener.barcraft" })
o.bind("SUPER + B", "Peek the bar", { ipc = "barcraft.reveal" })
o.bind("SUPER + SHIFT + B", "Next bar skin", { ipc = "barcraft.next" })
```

CLI / IPC commands:

```bash
omarchy-shell shell toggle thepixelgardener.barcraft   # open/close the Studio
omarchy-shell barcraft studio geometry                 # open on a tab: presets, colors, geometry, surface, behavior
omarchy-shell barcraft reveal                          # peek an auto-hidden bar out
omarchy-shell barcraft next                            # next skin (OSD), prints its name
omarchy-shell barcraft setSkin statusline              # any skin id, "standard" or "theme"
omarchy-shell barcraft toggleStandard                  # Omarchy's own bar look on/off
omarchy-shell barcraft toggleAutoHide
omarchy-shell barcraft followTheme
omarchy-shell barcraft current                         # skin id, "standard", "theme" or "draft"
omarchy-shell barcraft doctor                          # health report
```

---

## How it fits Omarchy

| Omarchy foundation | Barcraft |
| --- | --- |
| Feature settings in `shell.json` | `bar.barcraft`, beside `position`, `background` and `layout`; written via `mutateShellConfig`, so `omarchy bar reset` resets it too |
| User bar files in `~/.config/omarchy/bar/` | Saved skins in `~/.config/omarchy/bar/skins/` |
| Theme tokens in `shell.toml` / `shell.<section>.toml` | A theme ships its skin as `[bar-skin]` in `shell.toml` or `shell.bar-skin.toml` |
| `[bar]` icon tokens in `~/.config/omarchy/shell.toml` | Icon scale writes `[bar]` tokens marked `# barcraft`, never overwriting user lines |
| `omarchy-bar background` (Glassy, Hyprland blur) | Glass blur toggle drives the same switch |
| Omarchy menu extensions | Opt-in **Appearance → Menu Bar → Barcraft**, with a ✓ on the active skin |
| OSD (`omarchy osd`) | Skin switches via keybinding, right-click, or IPC show the skin name |
| `~/.config/omarchy/hooks/post-update.d/` | Opt-in check after Omarchy updates for upstream bar changes |
| [omacom/omarchy-ui](https://github.com/omacom/omarchy-ui) | Studio uses the vendored UI kit (`kit/`), matching Omarchy Control |
| `Style.duration`, `Translations`, `PlainText` | Follows animations toggle, live locale (English & German), and safe plain-text sinks |

---

## What Barcraft writes

- `~/.config/omarchy/shell.json` → `bar.barcraft`: active skin, standard switch, per-monitor skins, preferences, and unsaved draft. (Barcraft 0.2's `~/.config/omarchy/barcraft.toml` migrates once to `barcraft.toml.migrated`.)
- `~/.config/omarchy/bar/skins/*.toml`: skins you save in the Studio.
- `~/.config/omarchy/shell.toml`: only when a skin sets `icon-scale` != `1.00`; writes `[bar]` icon tokens marked `# barcraft` and removes them again at `1.00`.
- **Opt-in only** (toggled off by default in Studio → Behavior → Omarchy): a fenced `// barcraft:begin` … `// barcraft:end` block in `~/.config/omarchy/extensions/omarchy-menu.jsonc`, and `~/.config/omarchy/hooks/post-update.d/barcraft-sync`. Turning the toggles off removes them.
- Glass blur invokes `omarchy-bar background glassy|opaque`, the same switch as Omarchy's menu.

---

## Development

```bash
node tests/skinparser.test.js                          # parser, diagnostics, TOML, shell.json state, menu block, icon tokens
node tests/skinstore.test.js                           # atomic file I/O, failed delete, external edits, rename rollback, slow-save guards
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
omarchy plugin validate .
omarchy agent look plugin .
scripts/sync-upstream.sh --check                       # check if Omarchy's bar changed since last sync
scripts/sync-upstream.sh                               # 3-way merge Omarchy's bar into Bar.qml / BarModel.js
```

### Architecture notes

- **Vendored UI kit**: `kit/` tracks [omacom/omarchy-ui](https://github.com/omacom/omarchy-ui) at a pinned revision (`kit/KIT_REV`). `KitTheme.qml` bridges shell theme colors through `kit/Theme/ThemeSource.qml` (no C++ required). Update with `node tools/vendor-kit.js /path/to/omarchy-ui`.
- **Safe text input**: text fields use `LineField.qml` instead of Qt's `TextInput` to avoid Qt 6.12.0's clipboard-read stall inside the shell.
- **Upstream bar sync**: `Bar.qml` and `BarModel.js` layer Barcraft onto Omarchy's bar (`upstream/VERSION` + `upstream/*.orig`). After an Omarchy update, run `scripts/sync-upstream.sh` (and `--mark-synced` after resolving any conflict).
- **Engine lookup**: `BarWidget.qml` locates `barcraftEngine` by walking up its parent bar strip instead of a `.pragma library`, since Omarchy loads bar and widget entry points under distinct QML URLs.

| File | Role |
| --- | --- |
| [`SkinParser.js`](../SkinParser.js) | TOML subset, diagnostics, validation, built-in skins, `shell.json` state, menu block, icon tokens |
| [`SkinStore.qml`](../SkinStore.qml) | Verified atomic file I/O, saved-skin scanning, and `inotifywait` directory watching |
| [`SkinEngine.qml`](../SkinEngine.qml) | State, per-monitor drafts & saving, live previews, blur sync, clipboard, doctor |
| [`SkinLook.qml`](../SkinLook.qml) | Resolved colors & geometry (`"auto"` included) per bar surface and thumbnail |
| [`Bar.qml`](../Bar.qml) | Omarchy's bar with skinned surfaces, auto-hide, widget pills/chips, IPC |
| [`BarWidget.qml`](../BarWidget.qml), [`StudioContent.qml`](../StudioContent.qml) | Bar pill widget and keyboard-driven Studio panel |
| [`BarArtLayer.qml`](../BarArtLayer.qml), [`BarBezelOverlay.qml`](../BarBezelOverlay.qml), [`SkinThumbnail.qml`](../SkinThumbnail.qml) | Still art renderer, 3D bezels, and live Studio card previews |
| [`kit/`](../kit/), [`KitTheme.qml`](../KitTheme.qml), [`LineField.qml`](../LineField.qml) | Vendored Omarchy UI kit, theme bridge, and clipboard-safe line input |
