# Changelog

All notable changes to Barcraft are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
