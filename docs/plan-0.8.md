# Barcraft plan: 0.7.1, then 0.8

Written 2026-11-25. This replaces the two earlier drafts of the 0.8 plan.

## Where things stand

- 0.7.0 shipped on 2026-11-23. On 2026-11-25 the marketplace showed 269 detail views, 52 install-command copies and 2 hearts. Direct feedback so far is "like it" and "awesome", with nothing specific.
- A review found five bugs, all confirmed in the code. One leaves every new user without a way into Studio, and one contradicts the 0.7.0 release notes. They ship as a patch now instead of waiting for 0.8.

**Order:** 0.7.1 is fixes only, out within days. 0.8 is the share loop: you send someone your bar's look, they keep their own widgets, and they can go back.

---

## 0.7.1

### 1. Sync Omarchy's bar (r8098 → r8313)

**Why.** `Bar.qml` and `BarModel.js` are Omarchy's bar plugin with Barcraft's changes on top. Since the last sync, Omarchy has only changed the fullscreen check. Barcraft still uses the old one ([Bar.qml:1941](../Bar.qml)). As a result, a fullscreen window in a scrolling column outside the viewport, or one under a special workspace, makes the visible bar ignore clicks.

**Do**
- Run `scripts/sync-upstream.sh`, resolve any conflicts, and commit the sync on its own before any other `Bar.qml` change.
- Add `tests/barmodel.test.js` (`BarModel.js` already exports for node) and run it in CI's node step. Cases:
  - a real fullscreen window → true
  - a fullscreen column outside the viewport → false
  - a special workspace over a fullscreen window → false
  - 1 px rounding at fractional scale → true

**Done when**
- `scripts/sync-upstream.sh --check` exits 0.
- The visible bar takes clicks in all four cases, with auto-hide on and off.

### 2. Studio button on first install

**Why.** The README's `omarchy bar put thepixelgardener.barcraft` reports `ok` but places nothing. `setEnabled()` sees the `bar` kind, sets `bar.id` and returns before it places the widget ([PluginRegistry.qml:538](/usr/share/omarchy/shell/services/PluginRegistry.qml)). `barcraft studio` only works through that button ([Bar.qml:750](../Bar.qml)). A new user gets the bar and no way into Studio.

**Do**
- Put the layout logic in `BarModel.js` as a plain function, such as `placeStudioButton(config, id, fallbackLayout)`. It returns the edited config, or `null` when there is nothing to do. Only the primary `Bar.qml` instance calls it, once, through `mutateShellConfig`.
- **When it runs:** only when `bar.barcraft` does not exist yet, which means a genuine first run. The same write sets `bar.barcraft.studioButtonPlaced = true`.
- **Upgrading from 0.7:** if `bar.barcraft` exists and the flag doesn't, set the flag and leave the layout alone. Otherwise a 0.7 user who removed the button on purpose gets it back.
- **Startup order:** `loadState()` can call `persistState()` on startup ([SkinEngine.qml:967](../SkinEngine.qml)), which creates `bar.barcraft`. Read the first-run check from the config as loaded, before that runs, or the check never passes.
- **Missing layout:** if `bar.layout` is missing, first copy in the layout `Bar.qml` draws by default (`fallbackBarConfig.layout`). Never write a layout that holds only the button.
- **Where it goes:** at the end of `right`, the manifest's `defaultSection`. That's also where Omarchy puts a widget given no placement. Skip if the button is already anywhere in the layout.
- **Button removed later:** when `barcraft studio` (or `shell toggle thepixelgardener.barcraft`) finds no button, show a notification that names `omarchy-shell barcraft restoreButton`. Add that IPC function: it does the same insert without the first-run check. Don't build a second Studio host.
- **README install:** drop the `bar put` line. On a clean profile, check whether `omarchy bar use` is still needed after `omarchy plugin add … --enable`, since `setEnabled()` already sets `bar.id` for a bar plugin.
- **Upstream:** with your OK, report the early return to omacom/omarchy, with steps to reproduce and a suggested fix: for a manifest with both kinds, continue to widget placement after setting `bar.id`. Don't hold 0.7.1 for it.

**Tests** (node, `BarModel.js`)
- A missing layout keeps the stock widgets and adds the button.
- A customized layout keeps its order.
- A button that's already placed means no change.
- `bar.barcraft` without the flag gets the flag, and the layout is untouched.
- With the flag set and the button removed, the button stays removed.

### 3. Paste does what 0.7.0 promised

**Why.** The 0.7.0 changelog says a paste with a typo or an unknown preset keeps the current draft. In fact `importText()` applies the paste whenever `appliedCount > 0` ([SkinEngine.qml:781](../SkinEngine.qml)). So `name = "X"` plus `preset = "missing"` replaces the draft with default geometry.

**Rule**
- **Strict by default.** Any error rejects the paste. The draft, the skin on that display and the undo snapshot all stay as they were. Studio shows the first error with its line, key and suggestion.
- **Clamped numbers aren't errors.** They apply and report the adjustment, as they do today.
- **`name` and `description` alone don't count as applied.**
- **Skins from newer versions are the exception.** Exports write `format = 1`, and the parser accepts that key. If a pasted skin's `format` is higher than this version supports, apply the valid fields, list the ones skipped, and keep **Undo paste**.
- **Why the format line ships now and not in 0.8:** strict mode rejects unknown keys. Without it, the first 0.8 skin with a new key would fail to paste into 0.7.1.
- **Files on disk and theme skins stay tolerant**, as today. `doctor` reports their errors.
- Document `format` in `docs/skins.md`.

**Tests** (`skinparser` and engine)
- `name` plus an unknown preset → rejected; draft and undo kept.
- The typo `heigth = 34` → rejected, with a suggestion.
- `height = 999` → applied, with an adjustment.
- `format = 2` plus an unknown key → applied; the warning names the key.
- A `format = 1` export survives a round trip.
- A 0.7 export with no `format` line still pastes.

### 4. Save checks against the file the draft started from

**Why.** Saving in place sends `store.hashForPath(dest)` as the expected hash ([SkinEngine.qml:615](../SkinEngine.qml)). Once the watcher rescans after an outside edit, that's already the new file's hash. Save then overwrites the outside edit and reports success. The existing test only covers a save before the rescan ([tests/skinstore.test.js:227](../tests/skinstore.test.js)).

**Do**
- When a target goes from no draft to a draft, record the hash of the skin file it started from. Do this for the main draft and for each display's draft.
- Store it with the draft in `bar.barcraft` so it survives a restart.
- Save sends that hash. On a mismatch, keep both versions through the existing code-3 path: a notice, then either a confirmed overwrite or a save under a new name.
- A draft restored from 0.7.0 state has no recorded hash. Treat its starting point as unknown and ask before overwriting.
- Clear the hash when the draft is saved, reset or discarded.

**Tests**
- Edit, then rescan, then Save → blocked.
- Save before the rescan → blocked (the existing test).
- Restart with a stored draft, then an outside edit → blocked.
- A confirmed overwrite wins.
- A draft with no hash asks first.

### 5. Unplugging the display being edited

**Why.** Studio hides the monitor selector when there's only one screen ([StudioContent.qml:454](../StudioContent.qml)) but never resets `screenTarget`. If you undock while editing DP-2, your edits go to a display that isn't there and the selector is gone.

**Do.** When `screenTarget` drops out of `screenNames`, set it to `""` and clear `pendingPreview` and `confirmOverwriteName`. Keep that display's `monitorSkins` and `monitorDrafts`.

**Done when:** plugging the display back in restores its skin.

### 6. Docs and release

- README: say 9 built-in skins (Amiga is missing from the list) and use the new install block.
- CHANGELOG 0.7.1: say plainly that 0.7.0's note about pasting wasn't true and now is.
- i18n: add en and de strings for every new notice (CI checks that both files have the same keys).
- `manifest.json`: version 0.7.1.

### 0.7.1 release check

- These all pass:
  - the node tests (parser, store and the new barmodel tests)
  - `qmltestrunner` offscreen
  - `omarchy plugin validate .`
  - `omarchy agent look plugin .`
  - `scripts/sync-upstream.sh --check`
- **Clean profile.** Run the README install exactly as written. The stock widgets are intact, the button is there, and Studio opens from the button and from `omarchy-shell barcraft studio`.
- **Customized layout** with a third-party widget and a stock popup:
  - The widget order is kept.
  - Remove the button and restart the shell: it stays removed.
  - `barcraft studio` shows the restore notification.
- **Upgrade from 0.7.0** with the button removed: it stays removed.

---

## 0.8: share the look, keep your widgets

**The bet.** Other bar plugins already cover presets and layouts (Bar Skins), a live editor (Surface Studio) and per-monitor bars (Station). The one thing only Barcraft does: you send your bar's look as a TOML snippet, and the person who gets it keeps their own widgets and layout and can go back.

### Done on `dev` (ready for swap test)

1. **Unified Copy & Paste in Studio header + contextual Draft bar (covers #1 & #2):** **Copy** and **Paste** live once in `PanelHero.trailingControl` across every tab; a contextual Draft bar (`Save as skin name…`, `Save`, and `Undo paste` / `Reset`) appears on every tab — including **Skins** — whenever a paste or edit is active, and hides on clean tabs.
2. **Theme `[bar-skin]` errors visible on Skins (#3):** one-line error hint (with full list on hover) bound to `themeSkinInspection.errors`, even when the error prevents the theme skin from loading.
3. **Studio UI simplification & refactor:** moved **Fixed colors** into the **Custom** drawer, merged **Check updates** / **Update** into one stateful button, added **Share skins** in About, and extracted `StudioSkinCard.qml`.
4. **Synced Omarchy `r8313` → `r8442` & shrank `Bar.qml` merge surface:** adopted strip-sized `PanelWindow` + `frameSwapped` resize settle, fixed floating `edgeGap` clearance in `thicknessFor()` (panels/popups/toasts/drag-remove), and extracted `BarcraftHost.qml`, `BarAutoHide.qml`, and `SkinSurface.qml`.
5. **Security & Hyprland/Qt audit hardening:** 1 MiB cap on `READ_FILE_SCRIPT`, symlink guard before `chmod --reference`, O(1) `skippedSet` + bounded `adjustments`, `timeout -k 1 2` on `wl-paste`, `pipefail` + redirect/connect bounds on `curl`, `--` on `inotifywait`, and safe `formatNotice()`.

### Remaining before tagging 0.8.0

- ~~**Public share thread (#4):**~~ Done 2026-11-27: pinned issue [#4 "Share your skin"](https://github.com/thepixelgardener-create/barcraft/issues/4) with the `skin` label. `SkinEngine.shareSkinsUrl`, the README and `docs/skins.md` point to it.
- ~~**Refresh the README screenshots** in `assets/` (still from 0.4.0):~~ Done 2026-11-28: refreshed all 5 Studio screenshots, the 9-skin showcase (`assets/skins-showcase.webp` & `preview.webp`), `assets/social-preview.png`, and added an animated WebP demo (`assets/barcraft-demo.webp`).
- **Two-person swap test:** you and one other person each send the other a skin, starting from opening Studio, without help: copy, send, paste, keep or undo, then go back to your own skin or Omarchy standard. Every spot where either of you hesitates is a bug to fix before tagging `0.8.0`.
- ~~**Release check:**~~ Passed on `dev` 2026-11-27 (Hyprland 0.57.2-9, Qt 6.12.1, omarchy-dev r8457, whose bar is unchanged since r8442): node tests, `qmltestrunner` offscreen, `omarchy plugin validate .`, `omarchy agent look plugin .`, `scripts/sync-upstream.sh --check`. Re-run after any fix from the swap test, then bump `manifest.json` to 0.8.0.

---

## Not in 0.8

- **A skin gallery or online discovery.** Wait until someone asks where to find more skins.
- **More presets or more art.**
- **A second Studio host for opening Studio by keybinding without the button.** The notification and `restoreButton` cover that.
- **Splitting Barcraft into separate bar and widget plugins.**
- **Styling popups and menus.**

## Your decisions

1. **The upstream report.** Report the `setEnabled()` early return to omacom/omarchy? It's public, so it needs your OK.
2. **The swap test.** Who is the second person for the 0.8 test?
3. **The key name.** `format` is the proposal. Changing it later means a second migration, so settle it before 0.7.1 ships.
