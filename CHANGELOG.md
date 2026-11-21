# Changelog

All notable changes to Barcraft are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-11-21

### Added

- **Live skin reload**: Barcraft watches `~/.config/omarchy/bar/skins` (and the legacy `bar-skins` folder) with `inotifywait`, so a skin saved, renamed or deleted from an editor or a theme install shows up in Studio without a restart. It also notices when those folders are created or removed later. Without `inotifywait`, skins still load at startup as before.
- **Undo paste**: **Paste skin** saves a one-step checkpoint. **Undo paste** (Skins tab and Craft footer) restores the previous skin, draft and theme-follow state. Choosing, saving or resetting a skin clears it.

### Changed

- **Per-screen skins are fully per-screen**: a screen with its own skin now uses its own bar height, icon color and reserved space, for first-party widgets, custom commands and plugin widgets alike. Icon size and glass blur stay shared.
- Saved skins that inherit from each other (`preset = "<id>"`) resolve in one pass regardless of file order, including chains, cycles and user skins named after a built-in.
- Hook ownership checks recognise a 0.5.0/0.5.1 hook written in any shipped language, not only the current one.

## [0.5.2] - 2026-11-21

### Fixed

- **No lost edits to shared files**: Barcraft rewrites `omarchy-menu.jsonc` and `shell.toml` only while they still match what it read. The check runs right before the atomic rename; if another program saved in between, Barcraft reads the file again and retries (at most three times) instead of overwriting it.
- **Update hook ownership by content, not header**: the hook Barcraft writes now carries an MD5 digest of its own body. Barcraft replaces or removes it only while that digest still matches and the file is unchanged at that moment, so an edited hook is left alone even if it keeps the header. A hook from 0.5.0 or 0.5.1 counts as Barcraft's only when it is byte-identical to what that version wrote.
- **No file contents on command lines**: file writes and **Copy TOML** pass the content over stdin. Command lines carry only the path, an MD5 and flags.
- Rewritten files keep their permissions (0.5.1's temp-file writer left them at 0600).
- A hook conflict no longer leaves the hook sync stuck.

## [0.5.1] - 2026-11-21

### Fixed

- **Fresh `omarchy-menu.jsonc` reads**: `syncMenu()` now always reads the current on-disk `omarchy-menu.jsonc` before applying or removing Barcraft's fenced block, preventing stale startup snapshots from clobbering later user edits.
- **Ownership check on `post-update.d/barcraft-sync`**: Barcraft now inspects the existing hook for its ownership header (`# Added by Barcraft (thepixelgardener.barcraft).`) before overwriting or removing it, leaving user-maintained scripts untouched.
- **Verified atomic skin writes & renames**: `writeFile()` now writes via `mktemp` + `mv` in the target directory and byte-verifies the committed file (`cmp -s`) before reporting success or unlinking an old renamed skin, avoiding Quickshell `FileView` false-`saved` data loss.
- **Collision-safe skin saving**: distinct skin names that slugify to the same filename now allocate a unique slug (`-2`, `-3`, …) instead of silently overwriting, saving over a different skin with the same display name requires a second Save confirmation, and newly created skin files refuse to clobber existing unindexed files on disk.
- **Preserve user keys in `[bar]` on icon-scale reset**: `applyBarIconOverrides()` keeps a plain `[bar]` header in `~/.config/omarchy/shell.toml` whenever user-added keys exist under Barcraft's `[bar] # barcraft` section, and `applyIconScale()` now uses fresh on-disk read-modify-write.

## [0.5.0] - 2026-11-21

### Added

- **Preset #8 — `Statusline`**: a compact (26px), edge-to-edge, high-contrast developer statusline preset with outlined `chips` widgets and a subtle 1px divider rule that adapts live to any Omarchy theme.
- **Skin authoring documentation** (`docs/skins.md`) and full reference (`docs/reference.md`), keeping the root `README.md` concise and easy to scan.
- **Marketplace root preview** (`preview.webp`) for `plugins.omarchy.org`.

### Changed

- Updated the saved-skin path notice and TOML header comment to `~/.config/omarchy/bar/skins/<name>.toml`.

## [0.4.0] - 2026-11-20

Initial public release of Barcraft (`thepixelgardener.barcraft`) for Omarchy.

### Added

- **Skinnable Omarchy bar** (`Bar.qml`, `BarModel.js`, `SkinEngine.qml`, `SkinLook.qml`, `SkinParser.js`): wraps Omarchy's own bar plugin so every built-in and third-party `bar-widget`, popup, tooltip, drag-and-drop reorder, and multi-monitor layout works unchanged.
- **7 built-in skins** (all still, zero looping animations):
  - Classic: `Floating`, `Islands`, `Frosted`, `Capsule`, `Editorial`.
  - Wild Craft: `Matrix` (CRT phosphor terminal), `Runeforge` (chamfered obsidian and etched brass).
- **Omarchy standard switch**: toggle back to pixel-identical stock `omarchy.bar` appearance while keeping the Barcraft pill, Studio, and saved skins available.
- **Keyboard-driven Barcraft Studio** (`StudioContent.qml`, `BarWidget.qml`) built on the vendored Omarchy UI kit (`kit/`):
  - Five compact tabs: **Skins**, **Colors**, **Geometry**, **Surface**, and **Behavior**.
  - Live bar preview on hover or keyboard cursor movement, click/Enter to apply.
  - Full keyboard navigation (arrows / `hjkl`, `1`–`5` tabs, `Return` toggles Auto, `R` rename, `Del` delete, `Esc` close).
  - Theme-linked color swatches (`theme.<key>`), custom color picker (`ColorPickerField.qml`), automatic WCAG 4.5:1 text/icon contrast with optional manual override, separate text/icon contrast and surface depth controls, and 3D bezeling (`none`, `raised`, `inset`, `ridge`, `glass`).
  - Save, rename, delete, and share skins as `[bar-skin]` TOML via clipboard.
  - Per-monitor skin assignments ("Apply to").
- **Omarchy foundation integration**:
  - State stored under `bar.barcraft` in `~/.config/omarchy/shell.json` via `mutateShellConfig`.
  - Saved skins in `~/.config/omarchy/bar/skins/*.toml` and theme-shipped `[bar-skin]` support in `shell.toml` / `shell.bar-skin.toml`.
  - Automatic geometry tokens following theme `[bar] size-horizontal`, Omarchy panel gaps, Hyprland `gaps_out`, `decoration:rounding`, and theme bar alpha.
  - Icon scaling via `# barcraft`-marked `[bar]` tokens in `~/.config/omarchy/shell.toml`.
  - Glass blur synced with `omarchy-bar background`, OSD notifications on skin switches, IPC commands (`omarchy-shell barcraft ...`), optional Omarchy menu entries, and optional post-update drift hook (`scripts/sync-upstream.sh`).
- **Translations**: English (`i18n/en.json`) and German (`i18n/de.json`).
- **Security hardening & tests**:
  - Prototype-pollution guards, TOML injection hardening, symlink- and count-bounded skin scanning, `LineField.qml` (Wayland clipboard-safe text input), bounded clipboard/command timeouts, markup neutralization on OSD/tooltip sinks.
  - Automated parser/security suite (`tests/skinparser.test.js`) and offscreen Qt Quick test suite (`tests/tst_colorpicker.qml`, `tests/tst_linefield.qml`).
