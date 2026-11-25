# Changelog

All notable changes to Barcraft are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.1] - 2026-11-25

### Added

- **First-run Studio button placement & `restoreButton` IPC**: Barcraft now places its Studio button in the `right` section on first activation (preserving stock widgets even when `bar.layout` is absent from `shell.json`, and keeping customized layouts untouched on upgrade from 0.7.0 so deliberately removed buttons stay removed). Calling `omarchy-shell barcraft studio <tab>` or `omarchy-shell shell toggle thepixelgardener.barcraft` when the button is off the bar now sends a notification naming `omarchy-shell barcraft restoreButton`, which also rescues a button left in the drawer of a tray that is no longer on the bar. If Omarchy's stock layout can't be read, Barcraft writes no layout at all rather than a partial one.
- **Skin format versioning (`format = 1`)**: TOML exports now include `format = 1` under `[bar-skin]`. Pasting a skin with a higher `format` applies the fields this version understands, reports the skipped keys, and keeps **Undo paste**; unversioned skins from 0.7 and earlier continue to paste cleanly.
- **`tests/barmodel.test.js`**: added Node regression coverage for `BarModel.fullscreenOn` and first-run Studio button placement, wired into CI.

### Fixed

- **Strict paste validation (correction to 0.7.0 notes)**: 0.7.0's changelog stated that pasting a skin with a typo or unresolved `preset` preserved the current draft, which was not true when another key such as `name` parsed cleanly. **Paste skin** now rejects any hard error (syntax error, unknown key, duplicate key, invalid value, or unresolved `preset`, plus near-miss keys such as `heigth` in a paste without a `[bar-skin]` header), ignores metadata-only pastes (`name`/`description` alone), and preserves the selected display's draft and undo history untouched while still applying valid out-of-range clamped values with an adjustment notice.
- **Prevent Save from silently overwriting external edits after a rescan**: drafts now record the MD5 hash of the on-disk skin file they started from (persisted in `bar.barcraft` across restarts) rather than checking against the live post-rescan hash. External edits are blocked both before and after `inotifywait` rescans and across shell restarts; drafts restored from 0.7.0 state without a recorded base hash ask before overwriting.
- **Synced upstream Omarchy bar (`r8098` → `r8313`)**: brought in Omarchy's updated fullscreen geometry, special-workspace, and scrolling-column checks so a visible bar no longer stops accepting clicks when a fullscreen window sits offscreen or beneath a special workspace.
- **Save conflict edge cases**: saving a skin that still lives in the legacy `~/.config/omarchy/bar-skins/` folder, renaming a skin while a draft of it is open, and editing while a save is still being written no longer produce a false "changed on disk" warning. A skin scan that overlaps one of Barcraft's own writes is discarded and rerun, so it can't pair an old skin with the new file. A save still in flight when settings are reloaded from `shell.json` no longer clears the reloaded draft.
- **Overwrite confirmation stays with its display**: confirming an overwrite only applies to the display the warning was about, so switching or unplugging displays can't force-overwrite a skin with another display's look.
- **First-run detection on startup**: Barcraft no longer writes its settings before loading them, and waits for the 0.5-era `barcraft.toml` to finish loading, so an early IPC call can't hide a first run or skip the legacy migration.
- **Diagnostics stay bounded**: a skin file, theme or paste reports at most 20 problems ("…and N more") with short, control-character-free messages, so a hostile skin pack can no longer stall the shell. Skipped keys from newer-format skins on disk or in a theme now show up in `omarchy-shell barcraft doctor`, and a skin file with only a `name` loads again as it did in 0.7.0.
- **Active and saved skins survive large skin packs**: skin scanning now prioritizes the active skin, per-monitor skins, drafts, and skins saved or renamed in the current session ahead of the 200-file scan cap, and `omarchy-shell barcraft doctor` reports how many extra files were skipped past the limit instead of truncating silently.
- **Line separators in skin names**: U+2028/U+2029 in a name or description no longer break **Copy TOML** or saved files; bidi and zero-width control characters are stripped from names.
- **Unplugging the monitor being edited**: disconnecting the display currently selected in Studio now resets the target back to **Main skin** (clearing stale previews and overwrite confirmations) while preserving that display's saved `monitorSkins` and `monitorDrafts` for when it reconnects. The display selector also stays visible while a display is targeted, so unplugging the *other* monitor no longer hides the way back to **Main skin**.
- **README accuracy**: updated the built-in skin count from 8 to 9 (adding `Amiga`) and simplified the install command now that Barcraft activates and places its Studio button without the broken `omarchy bar put` step.

## [0.7.0] - 2026-11-23

### Added

- **Unified per-screen editing across all Studio tabs**: the monitor selector (**Main skin** or any display) stays pinned across **Skins**, **Colors**, **Geometry**, **Surface**, and **Behavior**. Editing a display creates a persisted per-screen draft (`bar.barcraft.monitorDrafts` in `shell.json`) without altering other displays, and **Copy TOML**, **Paste skin**, **Undo paste**, **Reset**, and **Save** all operate on the selected display. Shared controls (icon size, glass blur, and global auto-hide timing) are clearly labeled when targeting a single screen.
- **Actionable TOML diagnostics**: pasting a skin with typos (e.g. `heigth = 34`) or an unresolved preset preserves the current draft and reports the offending line, key, and closest suggestion. Clamped out-of-range values (e.g. `height = 999` → `56`) apply and report the adjusted value and line. `omarchy-shell barcraft doctor` reports diagnostics for both watched skin files and the active theme's `[bar-skin]`.
- **Extracted `SkinStore.qml` & filesystem test suite (`tests/skinstore.test.js`)**: isolates atomic file I/O, directory watching, and skin scanning from `SkinEngine.qml`, with temp-directory regression tests covering failed deletes, legacy sibling cleanup, concurrent external edits, rename rollback, and slow-save token guards.
- **About & Update section in Studio → Behavior**: displays version, license, author, GitHub/Issues links, an explicit on-demand **Check updates** button (strict HTTPS + semver validation, no background network calls), and an **Update** action that launches Omarchy's interactive `omarchy plugin update thepixelgardener.barcraft` terminal flow.
- **Amiga Wild Craft preset & upgraded Matrix / Runeforge art**: added the new **Amiga** preset (Workbench blue pixel bevels, OCS/ECS copper sheen, checkered Boing Ball gadget, and front-to-back depth gadget) and upgraded **Matrix** (multi-depth rain with glowing trails, aperture grille, PCB signal rails, telemetry pips, and bloom HUD brackets) and **Runeforge** (hammered basalt sheen, forged rivets, dwarven rail fretwork, keystone crests, and glowing Elder Futhark rune medallions).

### Changed

- **Reliable save, rename, and delete**: deleting a skin now confirms file removal (including shadowed copies in `~/.config/omarchy/bar-skins/`) before updating Studio state or reporting success; renaming verifies old-file removal and rolls back cleanly on failure; overwriting a skin modified externally warns before clobbering; and slow async saves no longer clear newer edits or skin switches.
- **Tighter `BarcraftMark` bar icon**: reduced default mark width from `1.4 × iconCanvas` (22×11 px) to `1.25 × iconSize` (15×9 px) with balanced inner proportions so it sits cleanly inside Omarchy's 27 px `iconSlot` alongside standard bar glyphs.
- **Cleaner TOML exports**: **Copy TOML** now mentions `shell.bar-skin.toml` in its header comment and omits inactive sub-keys (`theme-tint`, `bezel-strength`, `shadow-strength`, `border-alpha`/`border-width`, `hover-edge-px`/`accent-hairline`) when their parent feature is off.
- **Per-monitor Barcraft pill tooltip**: hovering the Barcraft widget on any display now reports the skin that display is wearing.

### Fixed

- Aligned all Studio slider limits with `SkinParser.js` (`height` 22–56, `edge-margin` 0–24, `side-margin` 0–48, `radius` 0–28, `bezel-strength` 0.15–1.0, `autohide-delay` 100–3000 ms).
- Disambiguated reserved skin names (`standard`, `draft`, `theme`, `theme-skin`) on both new saves and existing files on disk so a saved skin named `Standard` can no longer trigger **Omarchy standard** mode. A skin saved as `Draft` or `Standard` in 0.6 loads as `draft-saved` / `standard-saved`, and the bar and per-monitor choices that wore it move over with it.
- A broken or empty skin file no longer hides a working skin of the same name in the other skins folder, and `doctor` reports empty files as empty.
- Saving a skin keeps values for features that are switched off (e.g. `hover-edge-px` while the bar is always shown), so switching the feature back on restores them; only **Copy TOML** leaves them out.
- The **Amiga** preset shows its own Workbench blue and orange; tinting with the theme stays available through **Tint art with theme**.

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
