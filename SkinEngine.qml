import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "SkinParser.js" as SkinParser

// Barcraft's state: the chosen skin, saved skins, preferences, per-monitor
// skins and drafts, and the live preview. The bar owns the primary engine; the
// Studio widget finds it by walking up to the bar strip it sits in, so an edit
// shows on the bar at once.
Item {
  id: engine

  visible: false
  width: 0
  height: 0

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string configDir: homeDir + "/.config/omarchy"
  // Barcraft 0.2's own state file, read once to move it into shell.json.
  readonly property string legacyStatePath: configDir + "/barcraft.toml"
  // Saved skins sit with the rest of the bar's user files, beside Omarchy's
  // ~/.config/omarchy/bar/modules and bar/scripts. The 0.2 folder still loads.
  readonly property string userSkinsDir: configDir + "/bar/skins"
  readonly property string legacySkinsDir: configDir + "/bar-skins"
  readonly property string userShellTomlPath: configDir + "/shell.toml"
  readonly property string menuExtensionPath: configDir + "/extensions/omarchy-menu.jsonc"
  readonly property string updateHookPath: configDir + "/hooks/post-update.d/barcraft-sync"
  readonly property string pluginDir: {
    var raw = String(Qt.resolvedUrl(".")).replace(/^(?:file|qs):\/\//, "").replace(/\/$/, "")
    try { return decodeURIComponent(raw) } catch (e) { return raw }
  }
  readonly property string pluginVersion: manifest && manifest.version ? String(manifest.version) : ""
  readonly property string pluginAuthor: manifest && manifest.author ? String(manifest.author) : "frueh"
  readonly property string pluginLicense: manifest && manifest.license ? String(manifest.license) : "MIT"
  readonly property string repositoryUrl: "https://github.com/thepixelgardener-create/barcraft"
  readonly property string issuesUrl: "https://github.com/thepixelgardener-create/barcraft/issues"
  readonly property string remoteManifestUrl: "https://raw.githubusercontent.com/thepixelgardener-create/barcraft/main/manifest.json"

  // Explicit user-triggered Barcraft update check state:
  // "idle" | "checking" | "uptodate" | "available" | "ahead" | "error"
  property string updateState: "idle"
  property string remoteVersion: ""

  property bool isPrimary: true
  // Handed in by the bar: the shell's config facade (writes shell.json),
  // the `bar:` subtree it last loaded, the plugin manifest, and orientation.
  property var shellApi: null
  property var barConfig: null
  property var manifest: null
  property bool vertical: false
  property var ensureStudioButtonFn: null
  // Told by the bar: Omarchy's own background setting (omarchy-bar background).
  property bool barGlassy: false
  property bool barTransparent: false

  property string activeSkinId: "floating"
  property bool followTheme: true
  // Omarchy standard: show Omarchy's own bar look on every screen. Skins,
  // per-monitor choices and drafts stay put for when it goes off again.
  property bool standard: false
  property bool studioButtonPlaced: false
  // Open Studio panels editing this engine. While any is open the bar holds
  // its surface still, so live resizes don't blank the strip (Bar.qml).
  property int studioHolds: 0
  readonly property bool studioOpen: studioHolds > 0
  function holdStudio() { studioHolds++ }
  function releaseStudio() { studioHolds = Math.max(0, studioHolds - 1) }
  readonly property var builtinSkins: SkinParser.builtinSkins()
  readonly property var classicSkins: builtinSkins.filter(function(s) { return s.category !== "wild" })
  readonly property var wildSkins: builtinSkins.filter(function(s) { return s.category === "wild" })
  property var userSkins: []
  property var skinDiagnostics: []
  property int truncatedSkinCount: 0
  property var _recentSavedSlugs: []
  property string _lastPinnedRescanKey: ""
  property var customSkin: SkinParser.defaultSkin()
  property bool hasCustomDraft: false
  // MD5 of the on-disk skin file the main draft started from ("" if none/unknown).
  property string draftBaseHash: ""
  // screen name -> skin id ("theme" for the theme's skin).
  property var monitorSkins: ({})
  // screen name -> unsaved edited/pasted skin object for that screen.
  property var monitorDrafts: ({})
  // screen name -> MD5 of the on-disk skin file that screen's draft started from.
  property var monitorDraftBaseHashes: ({})
  // One-step undo checkpoints per target ("" for main skin, or screen name).
  property var pasteUndoSnapshots: ({})
  readonly property bool canUndoPaste: canUndoPasteFor("")
  // Monotonic edit token per target so an async save never clobbers newer edits.
  property var _editTokens: ({})
  property var prefs: SkinParser.defaultPrefs()
  property int revision: 0
  property bool stateLoaded: false
  property int _legacyWaits: 0
  // Set a moment after the saved state is in, so loading it never counts as
  // the user changing something (blur sync, icon tokens).
  property bool settled: false

  // A skin shown on the bar while a card is hovered or has the keyboard
  // cursor, without committing to it. "" previews on every screen that has
  // no override of its own.
  property var previewSkin: null
  property string previewScreen: ""
  readonly property bool previewing: previewSkin !== null

  // The active theme's colors.toml: ordered swatches and key -> hex.
  property var themePalette: []
  property var themeColors: ({})

  // Studio messages: a translation key, its %1, and whether it's an error.
  signal notice(string key, string arg, bool isError)
  // Emitted after a saved skin rename is confirmed on disk.
  signal skinRenamed(string oldId, string newId)

  readonly property var pinnedSkinSlugs: SkinParser.pinnedScanSlugs(
    activeSkinId, monitorSkins, hasCustomDraft ? customSkin : null,
    monitorDrafts, userSkins, builtinSkins, _recentSavedSlugs)

  function _rememberSavedSlug(slug) {
    var s = String(slug || "").trim()
    if (!s) return
    var next = [s]
    var prev = Array.isArray(_recentSavedSlugs) ? _recentSavedSlugs : []
    for (var i = 0; i < prev.length && next.length < 20; i++) {
      if (prev[i] !== s) next.push(prev[i])
    }
    _recentSavedSlugs = next
  }

  function _forgetSavedSlug(slug) {
    var s = String(slug || "").trim()
    if (!s || !Array.isArray(_recentSavedSlugs) || _recentSavedSlugs.indexOf(s) === -1) return
    _recentSavedSlugs = _recentSavedSlugs.filter(function(item) { return item !== s })
  }

  function _rescanIfPinnedMissing() {
    if (truncatedSkinCount <= 0) {
      _lastPinnedRescanKey = ""
      return
    }
    var slugs = pinnedSkinSlugs || []
    if (slugs.length === 0) return
    var missing = false
    for (var i = 0; i < slugs.length; i++) {
      var slug = slugs[i]
      if (isUserSkin(slug)) continue
      var foundByFile = false
      for (var j = 0; j < userSkins.length; j++) {
        var p = String(userSkins[j].path || "")
        if (p.slice(-slug.length - 6) === "/" + slug + ".toml") {
          foundByFile = true
          break
        }
      }
      if (!foundByFile) {
        missing = true
        break
      }
    }
    if (!missing) return
    var key = slugs.join(",")
    if (key === _lastPinnedRescanKey) return
    _lastPinnedRescanKey = key
    Qt.callLater(store.rescan)
  }

  SkinStore {
    id: store
    isPrimary: engine.isPrimary
    configDir: engine.configDir
    userSkinsDir: engine.userSkinsDir
    legacySkinsDir: engine.legacySkinsDir
    builtinSkins: engine.builtinSkins
    pinnedSlugs: engine.pinnedSkinSlugs
    onSkinsScanned: function(skins, diagnostics, renamedIds, truncatedCount) {
      engine.skinDiagnostics = diagnostics || []
      engine._renamedSkinIds = renamedIds || ({})
      engine.truncatedSkinCount = Number(truncatedCount) > 0 ? Math.floor(Number(truncatedCount)) : 0
      if (JSON.stringify(skins) !== JSON.stringify(engine.userSkins)) {
        engine.userSkins = skins
        engine.revision++
      }
      engine._migrateRenamedIds()
      engine._rescanIfPinnedMissing()
    }
  }

  readonly property var themeSkinInspection: {
    var _deps = engine.userSkins
    return SkinParser.inspectShellValues(Commons.Color.shellValues, function(id) { return engine.findSkinById(id) })
  }
  readonly property var themeSkin: themeSkinInspection ? themeSkinInspection.skin : null
  readonly property bool usingThemeSkin: followTheme && themeSkin !== null && !hasCustomDraft

  readonly property var committedSkin: {
    if (hasCustomDraft && customSkin) return customSkin
    if (followTheme && themeSkin) return themeSkin
    var found = findSkinById(activeSkinId)
    return found ? found : SkinParser.defaultSkin()
  }
  readonly property var activeSkin: (previewSkin && previewScreen === "") ? previewSkin : committedSkin

  // Standard holds unless a preview runs for that screen, so hovering a card
  // still shows the skin it would bring back.
  readonly property bool standardActive: standard && !(previewSkin && previewScreen === "")
  function standardFor(screenName) {
    if (!standard) return false
    return !(previewSkin && (previewScreen === "" || previewScreen === String(screenName || "")))
  }

  SkinLook {
    id: mainLook
    skin: engine.activeSkin
    paletteMap: engine.themeColors
    barGlassy: engine.barGlassy
    standard: engine.standardActive
    vertical: engine.vertical
  }
  readonly property var look: mainLook
  readonly property color effectiveForeground: mainLook.effectiveForeground
  // What the Studio's blur switch shows: whether Hyprland blurs the bar now.
  readonly property bool blurActive: barGlassy

  function resolveColorRef(ref) {
    return mainLook.resolveRef(ref)
  }

  // ---- Target helpers & token tracking -------------------------------------

  function normalizeTarget(screenName) {
    return String(screenName || "")
  }

  // Bumped when state is reloaded from shell.json: every pending save then
  // sees its target as changed.
  property int _tokenEpoch: 0

  function _tokenFor(screenName) {
    var key = normalizeTarget(screenName)
    return _tokenEpoch + ":" + ((_editTokens && _editTokens[key]) ? _editTokens[key] : 0)
  }

  function _bumpToken(screenName) {
    var key = normalizeTarget(screenName)
    var next = {}
    for (var k in _editTokens) next[k] = _editTokens[k]
    next[key] = (next[key] || 0) + 1
    _editTokens = next
    return next[key]
  }

  function _setMonitorDraft(screenName, skinObj) {
    var name = normalizeTarget(screenName)
    if (!name) return
    var next = {}
    for (var k in monitorDrafts) next[k] = monitorDrafts[k]
    if (skinObj) next[name] = skinObj
    else delete next[name]
    monitorDrafts = next
  }

  function _setPasteUndo(screenName, snap) {
    var key = normalizeTarget(screenName)
    var next = {}
    for (var k in pasteUndoSnapshots) next[k] = pasteUndoSnapshots[k]
    if (snap) next[key] = snap
    else delete next[key]
    pasteUndoSnapshots = next
  }

  function canUndoPasteFor(screenName) {
    var key = normalizeTarget(screenName)
    return !!(pasteUndoSnapshots && pasteUndoSnapshots[key])
  }

  function _draftBaseHashFor(screenName) {
    var name = normalizeTarget(screenName)
    if (!name) return SkinParser.sanitizeMd5(draftBaseHash)
    return (monitorDraftBaseHashes && monitorDraftBaseHashes[name])
      ? SkinParser.sanitizeMd5(monitorDraftBaseHashes[name]) : ""
  }

  function _setDraftBaseHash(screenName, hash) {
    var name = normalizeTarget(screenName)
    var clean = SkinParser.sanitizeMd5(hash)
    if (!name) {
      draftBaseHash = clean
      return
    }
    var next = {}
    for (var k in monitorDraftBaseHashes) next[k] = monitorDraftBaseHashes[k]
    if (clean) next[name] = clean
    else delete next[name]
    monitorDraftBaseHashes = next
  }

  function _captureDraftBaseHash(screenName) {
    var target = normalizeTarget(screenName)
    var baseId = targetBaseId(target)
    var baseSkin = baseId ? findSkinById(baseId) : null
    if (!baseSkin || baseSkin.source !== "user") return ""
    var path = baseSkin.path || skinPath(baseSkin.id)
    return SkinParser.sanitizeMd5(store.hashForPath(path))
  }

  // ---- Finding skins -------------------------------------------------------

  function findSkinById(id) {
    var target = String(id || "")
    for (var i = 0; i < userSkins.length; i++) {
      if (userSkins[i].id === target) return userSkins[i]
    }
    for (var j = 0; j < builtinSkins.length; j++) {
      if (builtinSkins[j].id === target) return builtinSkins[j]
    }
    var alias = SkinParser.canonicalSkinId(target)
    if (alias !== target) {
      for (var k = 0; k < builtinSkins.length; k++) {
        if (builtinSkins[k].id === alias) return builtinSkins[k]
      }
    }
    return null
  }

  function isUserSkin(id) {
    for (var i = 0; i < userSkins.length; i++) if (userSkins[i].id === id) return true
    return false
  }

  function monitorSkinFor(screenName) {
    var id = monitorSkins ? monitorSkins[normalizeTarget(screenName)] : undefined
    if (!id) return null
    if (id === "theme") return themeSkin
    return findSkinById(id)
  }

  function monitorDraftFor(screenName) {
    var name = normalizeTarget(screenName)
    if (!name || !monitorDrafts) return null
    return monitorDrafts[name] || null
  }

  function hasMonitorSkin(screenName) {
    return monitorDraftFor(screenName) !== null || monitorSkinFor(screenName) !== null
  }

  function hasDraftFor(screenName) {
    var name = normalizeTarget(screenName)
    return name ? (monitorDraftFor(name) !== null) : hasCustomDraft
  }

  // Canonical committed skin for a target ("" = Main skin, else screen name).
  function committedSkinFor(screenName) {
    var name = normalizeTarget(screenName)
    if (!name) return committedSkin
    var draft = monitorDraftFor(name)
    if (draft) return draft
    var own = monitorSkinFor(name)
    return own || committedSkin
  }

  // The skin a screen wears: its own draft or override if it has one, else the
  // main skin, with a preview on top while one runs for that screen.
  function skinForScreen(screenName) {
    var name = normalizeTarget(screenName)
    var own = name ? (monitorDraftFor(name) || monitorSkinFor(name)) : null
    if (previewSkin) {
      if (previewScreen === name) return previewSkin
      if (previewScreen === "" && !own) return previewSkin
    }
    return own || committedSkin
  }

  // The base saved/built-in id a target is currently assigned to (or "" if none).
  function targetBaseId(screenName) {
    var name = normalizeTarget(screenName)
    if (!name) return usingThemeSkin ? "theme" : activeSkinId
    var id = monitorSkins ? monitorSkins[name] : undefined
    return id ? String(id) : ""
  }

  // True if another target (main skin or another monitor) is using `id`.
  function isSkinShared(id, excludeScreen) {
    var slug = String(id || "")
    if (!slug) return false
    var skip = normalizeTarget(excludeScreen)
    if (skip !== "" && !usingThemeSkin && activeSkinId === slug) return true
    for (var s in monitorSkins) {
      if (s !== skip && monitorSkins[s] === slug) return true
    }
    return false
  }

  // What windows make room for, from committed skins only, so hovering a
  // preview never makes every tiled window jump.
  function barSizePxOf(skin) {
    var stock = vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
    if (!skin || skin.height === "auto") return stock
    var px = Style.space(Number(skin.height) || 30)
    return vertical ? Math.max(Style.bar.sizeVertical, px) : px
  }

  function edgePxOf(skin) {
    if (!skin || skin.mode === "edge") return 0
    return skin.edgeMargin === "auto" ? Style.gapsOut : Style.space(Number(skin.edgeMargin) || 0)
  }

  function zoneFor(screenName) {
    if (standard) return { standard: true, sizePx: barSizePxOf(null), edgePx: 0, autoHide: false }
    var own = committedSkinFor(screenName)
    return {
      standard: false,
      sizePx: barSizePxOf(own),
      edgePx: edgePxOf(own),
      autoHide: own.visibility === "autohide"
    }
  }

  // The id the Studio marks as chosen for a target ("" = draft or inheriting main).
  function chosenIdFor(screenName) {
    var name = normalizeTarget(screenName)
    if (standard) return name ? "" : "standard"
    if (name) {
      if (monitorDraftFor(name)) return ""
      var id = monitorSkins ? monitorSkins[name] : undefined
      return id ? String(id) : ""
    }
    if (usingThemeSkin) return "theme"
    return hasCustomDraft ? "" : activeSkinId
  }

  // ---- Choosing ------------------------------------------------------------

  function previewById(id, screenName) {
    var s = id === "theme" ? themeSkin : (id === "standard" ? SkinParser.standardSkin() : findSkinById(id))
    if (!s) return
    previewScreen = normalizeTarget(screenName)
    previewSkin = s
  }

  function clearPreview() {
    if (previewSkin !== null) previewSkin = null
    previewScreen = ""
  }

  function clearPasteUndo(screenName) {
    if (screenName === undefined) {
      if (Object.keys(pasteUndoSnapshots || {}).length > 0) pasteUndoSnapshots = ({})
      return
    }
    _setPasteUndo(screenName, null)
  }

  function setStandard(enabled) {
    clearPreview()
    clearPasteUndo()
    _bumpToken("")
    standard = !!enabled
    revision++
    persistState()
  }

  function selectSkin(id) {
    if (id === "standard") {
      setStandard(true)
      return true
    }
    if (id === "theme") {
      setFollowTheme(true)
      return true
    }
    var found = findSkinById(id)
    if (!found) return false
    clearPreview()
    clearPasteUndo("")
    _bumpToken("")
    standard = false
    activeSkinId = found.id
    hasCustomDraft = false
    _setDraftBaseHash("", "")
    customSkin = SkinParser.normalizeSkin(found, found.id, found.source)
    if (themeSkin) followTheme = false
    revision++
    persistState()
    return true
  }

  // Gives one screen its own skin; "" hands it back to the main skin.
  function selectForScreen(screenName, id) {
    var name = normalizeTarget(screenName)
    if (!name) {
      selectSkin(id)
      return
    }
    var next = {}
    for (var k in monitorSkins) next[k] = monitorSkins[k]
    if (!id) delete next[name]
    else next[name] = id === "theme" ? "theme" : String(id)
    clearPreview()
    clearPasteUndo(name)
    _bumpToken(name)
    _setMonitorDraft(name, null)
    _setDraftBaseHash(name, "")
    if (id) standard = false
    monitorSkins = next
    revision++
    persistState()
  }

  function setFollowTheme(enabled) {
    clearPreview()
    clearPasteUndo("")
    _bumpToken("")
    followTheme = !!enabled
    if (followTheme && themeSkin) standard = false
    if (followTheme && themeSkin) {
      hasCustomDraft = false
      _setDraftBaseHash("", "")
    }
    revision++
    persistState()
  }

  // Right-click on the widget: the theme's skin, the classic presets and the
  // saved skins, in a ring. Returns the name now on.
  function cycleSkin() {
    var ring = ["standard"]
    if (themeSkin) ring.push("theme")
    for (var i = 0; i < classicSkins.length; i++) ring.push(classicSkins[i].id)
    for (var j = 0; j < userSkins.length; j++) ring.push(userSkins[j].id)
    if (ring.length === 0) return ""
    var current = standard ? "standard" : (usingThemeSkin ? "theme" : activeSkinId)
    var idx = ring.indexOf(current)
    var next = ring[(idx + 1) % ring.length]
    selectSkin(next)
    return currentName()
  }

  // What the bar wears now, for the widget's tooltip and the IPC.
  function currentName(screenName) {
    var name = normalizeTarget(screenName)
    if (standardFor(name)) return strings.t("label.standard")
    var s = name ? committedSkinFor(name) : activeSkin
    return s ? s.name : ""
  }

  // The id the menu's checkmarks compare against.
  function currentId() {
    if (standard) return "standard"
    if (usingThemeSkin) return "theme"
    if (hasCustomDraft) return "draft"
    return activeSkinId
  }

  // Omarchy's on-screen display, as volume and brightness use it: for a
  // change made by keybinding, right-click or IPC, where no panel is open.
  function announce() {
    if (!isPrimary) return
    var payload = JSON.stringify({ icon: "󰍜", message: SkinParser.neutralizeMarkup(currentName()), duration: "1100" })
    runCommand(["omarchy-shell", "-q", "osd", "show", payload])
  }

  function notifyMissingStudioButton() {
    if (!isPrimary) return
    runCommand(["omarchy-notification-send", "-g", "󰍜", "Barcraft", strings.t("notify.missingButton")])
  }

  // ---- Editing -------------------------------------------------------------

  function updateField(key, value, screenName) {
    var target = normalizeTarget(screenName)
    clearPreview()
    standard = false
    var startingDraft = !hasDraftFor(target)
    if (startingDraft) _setDraftBaseHash(target, _captureDraftBaseHash(target))
    var base = committedSkinFor(target)
    var next = SkinParser.normalizeSkin(base, base.id, base.source)
    next[key] = value
    if (key === "mode") {
      if (value === "edge") {
        next.edgeMargin = 0
        next.sideMargin = 0
        next.radius = 0
      } else if (base.mode === "edge") {
        next.edgeMargin = 6
        next.sideMargin = 10
        if (next.radius === 0) next.radius = 12
      }
    }
    var normalized = SkinParser.normalizeSkin(next, next.id, "custom")
    _bumpToken(target)
    if (target) {
      _setMonitorDraft(target, normalized)
    } else {
      customSkin = normalized
      hasCustomDraft = true
    }
    revision++
    persistDebounce.restart()
  }

  function toggleAutoHide(screenName) {
    var target = normalizeTarget(screenName)
    var base = committedSkinFor(target)
    updateField("visibility", base.visibility === "autohide" ? "always" : "autohide", target)
  }

  // Blur is Omarchy's Glassy bar: omarchy-bar installs the Hyprland layer
  // rule globally, so toggling blur updates the shared (main) skin.
  function setBlur(enabled) {
    var want = !!enabled
    if (!!committedSkin.blur !== want) updateField("blur", want, "")
    Qt.callLater(engine.syncBlur)
  }

  // Icon scale writes global [bar] tokens in ~/.config/omarchy/shell.toml.
  function setSharedIconScale(scale) {
    updateField("iconScale", scale, "")
  }

  // Standard leaves blur to Omarchy's own background setting.
  readonly property bool committedBlur: !standard && !!(committedSkin && committedSkin.blur)
  onCommittedBlurChanged: if (isPrimary && settled) Qt.callLater(engine.syncBlur)

  function syncBlur() {
    if (!isPrimary || standard) return
    var want = committedBlur
    if (want === barGlassy) return
    // A clear bar the user picked stays clear; only asking for blur changes it.
    if (!want && barTransparent) return
    runCommand(["omarchy-bar", "background", want ? "glassy" : "opaque"])
  }

  function setPref(key, value) {
    var next = {}
    for (var k in prefs) next[k] = prefs[k]
    next[key] = value
    prefs = SkinParser.normalizePrefs(next)
    persistDebounce.restart()
    if (key === "omarchyMenu") Qt.callLater(engine.syncMenu)
    else if (key === "updateCheck") Qt.callLater(engine.syncUpdateHook)
  }

  function resetTarget(screenName) {
    var target = normalizeTarget(screenName)
    clearPreview()
    clearPasteUndo(target)
    _bumpToken(target)
    if (target) {
      _setMonitorDraft(target, null)
      _setDraftBaseHash(target, "")
      revision++
      persistState()
      return
    }
    standard = false
    hasCustomDraft = false
    _setDraftBaseHash("", "")
    var found = findSkinById(activeSkinId)
    customSkin = SkinParser.normalizeSkin(found || SkinParser.defaultSkin(), activeSkinId, "builtin")
    revision++
    persistState()
  }

  function resetToPreset() {
    resetTarget("")
  }

  // ---- Saved skins ---------------------------------------------------------

  function builtinIdTaken(slug) {
    return SkinParser.isReservedSkinId(slug, builtinSkins)
  }

  // A file name for a skin: never a built-in or reserved id, and when `unique`,
  // not another saved skin's either.
  function slugForName(name, ownId, unique) {
    var slug = SkinParser.slugify(name)
    if (builtinIdTaken(slug)) slug = (slug + "-custom").slice(0, 40)
    if (!unique) return slug
    var candidate = slug
    var n = 2
    while (candidate !== ownId && isUserSkin(candidate)) {
      candidate = (slug.slice(0, 36) + "-" + n)
      n++
    }
    return candidate
  }

  function skinPath(slug) {
    return userSkinsDir + "/" + slug + ".toml"
  }

  function replaceUserSkin(oldId, skin) {
    var updated = []
    var placed = false
    for (var i = 0; i < userSkins.length; i++) {
      var s = userSkins[i]
      if (s.id === skin.id || s.id === oldId) {
        if (!placed) updated.push(skin)
        placed = true
      } else {
        updated.push(s)
      }
    }
    if (!placed) updated.push(skin)
    userSkins = updated
  }

  function saveUserSkin(rawName, forceOverwrite, screenName) {
    var targetScreen = normalizeTarget(screenName)
    var sourceSkin = committedSkinFor(targetScreen)
    var cleanName = SkinParser.sanitizeLabel(rawName, 40)
    if (!cleanName) cleanName = sourceSkin.name || "Custom"
    // Only allow silent in-place overwrite when this target exclusively owns
    // the base skin; if another monitor shares it, prompt for confirmation.
    var baseId = targetBaseId(targetScreen)
    var inPlaceId = (baseId && !isSkinShared(baseId, targetScreen)) ? baseId : ""
    var target = SkinParser.resolveSaveTarget(cleanName, userSkins, inPlaceId, builtinIdTaken, !!forceOverwrite)
    if (target.needsConfirm) {
      return { ok: false, needsConfirm: true, slug: target.slug, conflictName: target.conflictName }
    }
    var slug = target.slug
    var existing = target.overwrite ? findSkinById(slug) : null
    var dest = (existing && existing.path && SkinParser.isSafeSkinPath(existing.path, [userSkinsDir])) ? existing.path : skinPath(slug)
    var toSave = SkinParser.normalizeSkin(sourceSkin, slug, "user")
    toSave.id = slug
    toSave.name = cleanName
    toSave.source = "user"
    toSave.path = dest
    var capturedToken = _tokenFor(targetScreen)
    var expectHash = ""
    // A skin from the legacy folder is saved into the new one: there is no
    // file there to compare against, only one that must not appear meanwhile.
    var movingFromLegacy = !!(existing && existing.path && existing.path !== dest)
    if (target.overwrite && !forceOverwrite && movingFromLegacy) {
      expectHash = "missing"
    } else if (target.overwrite && !forceOverwrite) {
      if (hasDraftFor(targetScreen)) {
        expectHash = _draftBaseHashFor(targetScreen)
        if (!expectHash) {
          return { ok: false, needsConfirm: true, slug: target.slug, conflictName: cleanName }
        }
      } else {
        expectHash = SkinParser.sanitizeMd5(store.hashForPath(dest))
        if (!expectHash) {
          return { ok: false, needsConfirm: true, slug: target.slug, conflictName: cleanName }
        }
      }
    }

    store.writeFile(dest, SkinParser.serializeToml(toSave), function(ok, code) {
      if (!ok) {
        if (code === 3) {
          store.rescan()
          engine.notice("status.saveChangedExternally", cleanName, true)
        } else {
          engine.notice(code === 2 ? "status.saveExists" : "status.saveFailed", slug, true)
        }
        return
      }
      engine.replaceUserSkin(slug, toSave)
      engine._rememberSavedSlug(slug)
      // Only clear the target's draft and bind the new skin if the user hasn't
      // edited or switched that target while the write was in flight.
      if (engine._tokenFor(targetScreen) !== capturedToken) {
        if (engine.hasDraftFor(targetScreen) && engine.targetBaseId(targetScreen) === slug) {
          engine._setDraftBaseHash(targetScreen, store.hashForPath(dest))
          persistDebounce.restart()
        }
        engine.revision++
        engine.notice("status.savedKeptDraft", slug, false)
        return
      }
      engine.clearPreview()
      engine.clearPasteUndo(targetScreen)
      engine.standard = false
      engine._setDraftBaseHash(targetScreen, "")
      if (targetScreen) {
        var mons = {}
        for (var k in engine.monitorSkins) mons[k] = engine.monitorSkins[k]
        mons[targetScreen] = slug
        engine.monitorSkins = mons
        engine._setMonitorDraft(targetScreen, null)
      } else {
        engine.activeSkinId = slug
        engine.hasCustomDraft = false
        engine.customSkin = toSave
        if (engine.themeSkin) engine.followTheme = false
      }
      engine.revision++
      engine.persistState()
      engine.notice("status.saved", slug, false)
    }, { noClobber: !target.overwrite, expect: expectHash })
    return { ok: true, needsConfirm: false, slug: slug, conflictName: "" }
  }

  function renameUserSkin(id, rawName) {
    var skin = null
    for (var i = 0; i < userSkins.length; i++) if (userSkins[i].id === id) skin = userSkins[i]
    var cleanName = SkinParser.sanitizeLabel(rawName, 40)
    if (!skin || !cleanName || cleanName === skin.name) return ""
    clearPreview()
    var slug = slugForName(cleanName, id, true)
    var oldPath = skin.path || skinPath(id)
    var renamed = SkinParser.normalizeSkin(skin, slug, "user")
    renamed.id = slug
    renamed.name = cleanName
    renamed.source = "user"
    renamed.path = skinPath(slug)
    var sameFile = oldPath === renamed.path
    var removeOld = (!sameFile && SkinParser.isSafeSkinPath(oldPath, [engine.userSkinsDir, engine.legacySkinsDir])) ? oldPath : ""
    var oldHash = SkinParser.sanitizeMd5(store.hashForPath(oldPath))

    // Write and byte-verify the replacement file on disk and confirm oldPath
    // removal before updating Studio state.
    store.writeFile(renamed.path, SkinParser.serializeToml(renamed), function(ok, code) {
      if (!ok) {
        if (code === 4) {
          store.rescan()
          engine.notice("status.renamePartial", cleanName, true)
        } else {
          engine.notice(code === 2 ? "status.saveExists" : "status.saveFailed", slug, true)
        }
        return
      }
      engine.replaceUserSkin(id, renamed)
      engine._forgetSavedSlug(id)
      engine._rememberSavedSlug(slug)
      // A draft that started from the old file now starts from the renamed
      // one, unless the old file had already changed under it.
      var newHash = store.hashForPath(renamed.path)
      function carryBase(screen) {
        var had = engine._draftBaseHashFor(screen)
        if (had) engine._setDraftBaseHash(screen, had === oldHash ? newHash : "")
      }
      if (engine.activeSkinId === id && engine.hasCustomDraft) carryBase("")
      for (var ds in engine.monitorSkins) {
        if (engine.monitorSkins[ds] === id && engine.hasDraftFor(ds)) carryBase(ds)
      }
      if (engine.activeSkinId === id) {
        engine.activeSkinId = slug
        if (!engine.hasCustomDraft) engine.customSkin = renamed
      }
      var mons = {}
      for (var screen in engine.monitorSkins) {
        mons[screen] = engine.monitorSkins[screen] === id ? slug : engine.monitorSkins[screen]
      }
      engine.monitorSkins = mons
      engine.revision++
      engine.persistState()
      engine.skinRenamed(id, slug)
      engine.notice("status.renamed", cleanName, false)
      if (removeOld) store.removeLegacySibling(removeOld)
    }, { noClobber: !sameFile, removeAfter: removeOld })
    return slug
  }

  function deleteUserSkin(id) {
    var victim = null
    for (var i = 0; i < userSkins.length; i++) {
      if (userSkins[i].id === id) victim = userSkins[i]
    }
    if (!victim) return
    clearPreview()
    var victimPath = victim.path || skinPath(id)

    // Only remove from state and report success after confirmed file removal.
    store.removeSkinFiles([victimPath], function(ok) {
      if (!ok) {
        store.rescan()
        engine.notice("status.deleteFailed", victim.name, true)
        return
      }
      var kept = []
      for (var j = 0; j < engine.userSkins.length; j++) {
        if (engine.userSkins[j].id !== id) kept.push(engine.userSkins[j])
      }
      // The bar doesn't change under you: a deleted skin that's on stays on as
      // an unsaved draft until something else is picked.
      if (engine.activeSkinId === id && !engine.hasCustomDraft && !engine.usingThemeSkin) {
        engine.customSkin = SkinParser.normalizeSkin(victim, id, "custom")
        engine.hasCustomDraft = true
        engine._setDraftBaseHash("", "")
      }
      engine.userSkins = kept
      engine._forgetSavedSlug(id)
      var mons = {}
      for (var screen in engine.monitorSkins) {
        if (engine.monitorSkins[screen] !== id) mons[screen] = engine.monitorSkins[screen]
        else engine._setDraftBaseHash(screen, "")
      }
      engine.monitorSkins = mons
      engine.revision++
      engine.persistState()
      engine.notice("status.deleted", victim.name, false)
      store.removeLegacySibling(victimPath)
    })
  }

  // ---- Clipboard -----------------------------------------------------------

  function exportToml(screenName) {
    return SkinParser.serializeToml(committedSkinFor(screenName), { compact: true })
  }

  function exportActiveToml() {
    return exportToml("")
  }

  // The TOML goes to wl-copy over stdin, never as an argument.
  function copyToml(screenName) {
    store.runJob(["wl-copy"], exportToml(screenName), function(code) {
      if (code === 0) engine.notice("status.copied", "", false)
      else engine.notice("status.copyFailed", "", true)
    })
  }

  function copyActiveToml() {
    copyToml("")
  }

  property string _pasteTarget: ""

  function importFromClipboard(screenName) {
    if (pasteProc.running) return
    _pasteTarget = normalizeTarget(screenName)
    pasteProc.running = true
  }

  function importText(text, screenName) {
    var target = normalizeTarget(screenName)
    var raw = String(text || "")
    if (raw.length > 32768) {
      notice("status.importTooLarge", "", true)
      return false
    }
    var res = SkinParser.inspectToml(raw, "imported", "custom", function(id) { return engine.findSkinById(id) })
    if (res.errors && res.errors.length > 0) {
      notice("status.importError", res.errors[0].message, true)
      return false
    }
    // A paste has to change the look: a name or description alone is not a skin.
    if (!res.skin || !(res.styleCount > 0)) {
      if (res.newerFormat && res.skippedKeys && res.skippedKeys.length > 0) {
        notice("status.importUnsupported", res.skippedSummary, true)
      } else {
        notice("status.importFailed", "", true)
      }
      return false
    }
    var skin = res.skin
    var prevBaseHash = _draftBaseHashFor(target)
    if (target) {
      var prevDraft = monitorDraftFor(target)
      _setPasteUndo(target, {
        screen: target,
        monitorSkinId: monitorSkins && monitorSkins[target] ? monitorSkins[target] : "",
        hadDraft: prevDraft !== null,
        draftSkin: prevDraft ? SkinParser.normalizeSkin(prevDraft, prevDraft.id, prevDraft.source) : null,
        draftBaseHash: prevDraft !== null ? prevBaseHash : "",
        standard: standard
      })
      clearPreview()
      _bumpToken(target)
      standard = false
      _setMonitorDraft(target, skin)
      _setDraftBaseHash(target, "")
    } else {
      var prevSkin = committedSkin
      _setPasteUndo("", {
        screen: "",
        activeSkinId: activeSkinId,
        followTheme: followTheme,
        standard: standard,
        hasCustomDraft: hasCustomDraft,
        draftBaseHash: hasCustomDraft ? prevBaseHash : "",
        customSkin: prevSkin ? SkinParser.normalizeSkin(prevSkin, prevSkin.id, prevSkin.source) : null
      })
      clearPreview()
      _bumpToken("")
      standard = false
      customSkin = skin
      hasCustomDraft = true
      _setDraftBaseHash("", "")
    }
    revision++
    persistState()
    if (res.newerFormat) {
      var skipped = res.skippedSummary
      var fmtNote = (res.skippedKeys && res.skippedKeys.length > 0)
        ? strings.t("status.skippedNote").replace("%1", function() { return skipped })
        : strings.t("status.newerFormatNote")
      notice("status.importedAdjusted", skin.name + " (" + fmtNote + ")", false)
    } else if (res.adjustments && res.adjustments.length > 0) {
      notice("status.importedAdjusted", skin.name + " (" + res.adjustments[0].message + ")", false)
    } else {
      notice("status.imported", skin.name, false)
    }
    return true
  }

  function undoPaste(screenName) {
    var target = normalizeTarget(screenName)
    var snap = pasteUndoSnapshots ? pasteUndoSnapshots[target] : null
    if (!snap) return false
    _setPasteUndo(target, null)
    clearPreview()
    _bumpToken(target)
    if (target) {
      standard = !!snap.standard
      var mons = {}
      for (var k in monitorSkins) mons[k] = monitorSkins[k]
      if (snap.monitorSkinId) mons[target] = snap.monitorSkinId
      else delete mons[target]
      monitorSkins = mons
      _setMonitorDraft(target, snap.hadDraft && snap.draftSkin
        ? SkinParser.normalizeSkin(snap.draftSkin, snap.draftSkin.id, "custom")
        : null)
      _setDraftBaseHash(target, snap.hadDraft ? (snap.draftBaseHash || "") : "")
      revision++
      persistState()
      notice("status.pasteUndone", currentName(target), false)
      return true
    }
    activeSkinId = snap.activeSkinId
    followTheme = snap.followTheme
    standard = snap.standard
    var missingSaved = !snap.hasCustomDraft && !snap.standard && !(snap.followTheme && themeSkin) && !findSkinById(snap.activeSkinId)
    hasCustomDraft = snap.hasCustomDraft || (missingSaved && !!snap.customSkin)
    _setDraftBaseHash("", snap.hasCustomDraft ? (snap.draftBaseHash || "") : "")
    if (snap.customSkin) {
      customSkin = SkinParser.normalizeSkin(snap.customSkin, snap.customSkin.id, hasCustomDraft ? "custom" : snap.customSkin.source)
    }
    revision++
    persistState()
    notice("status.pasteUndone", currentName(""), false)
    return true
  }

  // ---- Settings: shell.json `bar.barcraft` ---------------------------------

  readonly property var configBlock: barConfig && typeof barConfig === "object"
    && barConfig.barcraft && typeof barConfig.barcraft === "object" ? barConfig.barcraft : null
  property string _lastConfigJson: ""
  property bool migrated: false

  onConfigBlockChanged: if (stateLoaded) Qt.callLater(engine.applyConfigBlock)

  function stateJson() {
    return JSON.stringify(SkinParser.stateToJson(
      activeSkinId, followTheme, hasCustomDraft ? customSkin : null,
      prefs, monitorSkins, standard, monitorDrafts,
      {
        studioButtonPlaced: studioButtonPlaced,
        draftBaseHash: hasCustomDraft ? draftBaseHash : "",
        monitorDraftBaseHashes: monitorDraftBaseHashes
      }))
  }

  function _studioButtonChanged(result) {
    return result === "restored" || result === "flagged"
  }

  function persistState() {
    persistDebounce.stop()
    if (!stateLoaded) {
      persistDebounce.restart()
      return
    }
    if (!isPrimary || !shellApi || typeof shellApi.mutateShellConfig !== "function") return
    var json = stateJson()
    if (json === _lastConfigJson) return
    _lastConfigJson = json
    shellApi.mutateShellConfig(function(config) {
      if (!config.bar || typeof config.bar !== "object") config.bar = {}
      config.bar.barcraft = JSON.parse(json)
    })
  }

  // 0.6 could save a skin as draft.toml or standard.toml. Those ids are
  // reserved now, so the files load as "draft-saved" / "standard-saved", and
  // a stored choice of the old id moves over instead of losing the look.
  property var _renamedSkinIds: ({})
  function _migrateRenamedIds() {
    var map = _renamedSkinIds || {}
    if (!stateLoaded) return
    function moved(id) {
      var key = String(id || "")
      if (key !== "draft" && key !== "standard") return ""
      return Object.prototype.hasOwnProperty.call(map, key) ? String(map[key]) : ""
    }
    var changed = false
    var nextActive = moved(activeSkinId)
    if (nextActive) {
      activeSkinId = nextActive
      changed = true
    }
    var mons = {}
    for (var screen in monitorSkins) {
      var to = moved(monitorSkins[screen])
      mons[screen] = to || monitorSkins[screen]
      if (to) changed = true
    }
    if (!changed) return
    monitorSkins = mons
    revision++
    persistState()
  }

  function applyState(st) {
    _tokenEpoch++
    clearPasteUndo()
    activeSkinId = st.activeSkinId
    followTheme = st.followTheme
    standard = !!st.standard
    studioButtonPlaced = !!st.studioButtonPlaced
    prefs = st.prefs
    monitorSkins = st.monitors || ({})
    monitorDrafts = st.monitorDrafts || ({})
    monitorDraftBaseHashes = st.monitorDraftBaseHashes || ({})
    if (st.draft) {
      customSkin = st.draft
      hasCustomDraft = true
      draftBaseHash = st.draftBaseHash || ""
    } else {
      hasCustomDraft = false
      draftBaseHash = ""
    }
    revision++
  }

  function applyConfigBlock() {
    var block = configBlock
    if (!block) return
    var st = SkinParser.stateFromJson(block, function(id) { return engine.findSkinById(id) })
    var json = JSON.stringify(SkinParser.stateToJson(
      st.activeSkinId, st.followTheme, st.draft, st.prefs, st.monitors, st.standard, st.monitorDrafts,
      {
        studioButtonPlaced: st.studioButtonPlaced,
        draftBaseHash: st.draftBaseHash,
        monitorDraftBaseHashes: st.monitorDraftBaseHashes
      }))
    if (json === _lastConfigJson) return
    _lastConfigJson = json
    applyState(st)
    if (settled) Qt.callLater(engine.syncIntegration)
  }

  // Barcraft 0.2 kept its state in ~/.config/omarchy/barcraft.toml. Moved
  // into shell.json once; the old file is kept as barcraft.toml.migrated.
  function applyLegacyText(raw) {
    var st = SkinParser.parseStateToml(raw)
    st.draft = SkinParser.parseToml(raw, st.activeSkinId, "custom", function(id) { return engine.findSkinById(id) })
    applyState(st)
  }

  function loadState() {
    if (stateLoaded) return
    if (configBlock) {
      applyConfigBlock()
      if (isPrimary && !studioButtonPlaced && typeof ensureStudioButtonFn === "function") {
        if (_studioButtonChanged(ensureStudioButtonFn(false))) {
          studioButtonPlaced = true
          _lastConfigJson = stateJson()
        }
      }
    } else {
      if (isPrimary && legacyStateView.path && !legacyStateView.settled && _legacyWaits++ < 25) {
        loadTimer.restart()
        return
      }
      var hasLegacy = isPrimary && legacyStateView.loaded && !!(legacyStateView.text() || "").trim()
      if (hasLegacy) {
        applyLegacyText(legacyStateView.text())
      }
      if (isPrimary && typeof ensureStudioButtonFn === "function") {
        if (_studioButtonChanged(ensureStudioButtonFn(false))) {
          studioButtonPlaced = true
          if (!hasLegacy) _lastConfigJson = stateJson()
        }
      }
      if (hasLegacy) {
        persistState()
        migrated = true
        runCommand(["mv", "-n", "--", legacyStatePath, legacyStatePath + ".migrated"])
      }
    }
    stateLoaded = true
    _migrateRenamedIds()
    _rescanIfPinnedMissing()
    settleTimer.restart()
  }

  FileView {
    id: legacyStateView
    property bool loaded: false
    property bool settled: false
    path: engine.isPrimary ? engine.legacyStatePath : ""
    printErrors: false
    watchChanges: false
    onLoaded: { loaded = true; settled = true }
    onLoadFailed: settled = true
  }

  Timer {
    id: loadTimer
    interval: 400
    repeat: false
    onTriggered: engine.loadState()
  }

  // Commands run one after another, never cancelling the one before.
  property var _commandQueue: []

  function runCommand(argv) {
    var next = _commandQueue.concat([argv])
    if (next.length > 32) next = next.slice(next.length - 32)
    _commandQueue = next
    if (!commandProc.running) _nextCommand()
  }

  function _nextCommand() {
    if (commandProc.running || _commandQueue.length === 0) return
    commandProc.command = _commandQueue[0]
    _commandQueue = _commandQueue.slice(1)
    commandProc.running = true
    commandWatchdog.restart()
  }

  Timer {
    id: commandWatchdog
    interval: 8000
    repeat: false
    onTriggered: {
      if (!commandProc.running) return
      console.warn("Barcraft: command timed out, stopping: " + JSON.stringify(commandProc.command))
      commandProc.running = false
      Qt.callLater(engine._nextCommand)
    }
  }

  Process {
    id: commandProc
    onExited: {
      commandWatchdog.stop()
      Qt.callLater(engine._nextCommand)
    }
  }

  function rescanUserSkins() {
    store.rescan()
  }

  Timer {
    id: persistDebounce
    interval: 120
    repeat: false
    onTriggered: engine.persistState()
  }

  Timer {
    id: settleTimer
    interval: 1500
    repeat: false
    onTriggered: {
      engine.settled = true
      engine.applyIconScale()
      engine.syncIntegration()
    }
  }

  FileView {
    id: themeColorsView
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var raw = text()
      engine.themePalette = SkinParser.parseThemeColorsToml(raw)
      engine.themeColors = SkinParser.themeColorMap(raw)
    }
    onFileChanged: reload()
  }

  Connections {
    target: Commons.Color
    function onShellValuesChanged() { themeColorsView.reload() }
  }

  // ---- Omarchy integration: menu entries and the post-update check --------

  Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function menuEntries() {
    var parent = "appearance.top-bar.barcraft"
    var pill = "󰍜"
    var check = function(id) { return "[[ $(omarchy-shell -q barcraft current) == " + shellQuoteSingle(id) + " ]]" }
    var rows = [
      [parent, { icon: pill, label: "Barcraft", when: "omarchy-shell barcraft ping >/dev/null 2>&1" }],
      [parent + ".studio", { icon: "󰏘", label: strings.t("menu.studio"), action: "omarchy-shell shell toggle thepixelgardener.barcraft" }],
      [parent + ".standard", { icon: "󰍜", label: strings.t("label.standard"), checked: check("standard"), action: "omarchy-shell barcraft setSkin standard" }]
    ]
    if (themeSkin) rows.push([parent + ".theme", { icon: "󰏘", label: strings.t("card.theme"), checked: check("theme"), action: "omarchy-shell barcraft setSkin theme" }])
    for (var i = 0; i < builtinSkins.length; i++) {
      var b = builtinSkins[i]
      if (!/^[a-z0-9_-]+$/.test(String(b.id || ""))) continue
      rows.push([parent + "." + b.id, { icon: b.category === "wild" ? "󰏘" : "󰍜", label: b.name, checked: check(b.id), action: "omarchy-shell barcraft setSkin " + shellQuoteSingle(b.id) }])
    }
    return rows
  }

  function shellQuoteSingle(text) {
    return "'" + String(text).replace(/\0/g, "").replace(/'/g, "'\\''") + "'"
  }

  function updateHookScript() {
    return SkinParser.updateHookScript(pluginDir, strings.t("hook.changed"), Qt.md5)
  }

  function legacyUpdateHookScripts() {
    return SkinParser.legacyUpdateHookScripts(pluginDir)
  }

  property bool _menuSyncBusy: false
  property bool _menuSyncAgain: false
  property bool _hookSyncBusy: false
  property bool _hookSyncAgain: false
  property bool _iconSyncBusy: false
  property bool _iconSyncAgain: false

  function syncIntegration() {
    if (!isPrimary || !settled) return
    syncMenu()
    syncUpdateHook()
  }

  function syncMenu() {
    if (!isPrimary || !settled) return
    if (_menuSyncBusy) {
      _menuSyncAgain = true
      return
    }
    _menuSyncBusy = true
    _menuSyncAgain = false
    var want = !!prefs.omarchyMenu

    store.editSharedFile(menuExtensionPath, function(current) {
      if (!want && current.indexOf("barcraft:begin") < 0) return null
      return SkinParser.applyMenuBlock(current, want ? engine.menuEntries() : null)
    }, function() {
      engine._menuSyncBusy = false
      if (engine._menuSyncAgain) Qt.callLater(engine.syncMenu)
    })
  }

  function syncUpdateHook() {
    if (!isPrimary || !settled) return
    if (_hookSyncBusy) {
      _hookSyncAgain = true
      return
    }
    _hookSyncBusy = true
    _hookSyncAgain = false
    var want = !!prefs.updateCheck

    function finish() {
      engine._hookSyncBusy = false
      if (engine._hookSyncAgain) Qt.callLater(engine.syncUpdateHook)
    }

    store.readTextFile(updateHookPath, function(status, text) {
      if (status === "missing") {
        if (!want) {
          finish()
          return
        }
        store.writeFile(engine.updateHookPath, engine.updateHookScript(), function() { finish() },
          { expect: "missing", chmodExec: true })
        return
      }

      var pristine = status === "ok"
        && SkinParser.isPristineUpdateHook(text, Qt.md5, engine.legacyUpdateHookScripts())
      if (pristine && !want) {
        store.removeFileIfUnchanged(engine.updateHookPath, Qt.md5(text), function() { finish() })
        return
      }
      if (pristine) {
        var desired = engine.updateHookScript()
        if (text === desired) {
          finish()
          return
        }
        store.writeFile(engine.updateHookPath, desired, function() { finish() },
          { expect: Qt.md5(text), chmodExec: true })
        return
      }
      if (!want) {
        finish()
        return
      }

      console.warn("Barcraft: keeping existing " + updateHookPath + " (not Barcraft's, or edited since)")
      if (engine.prefs.updateCheck) {
        var nextPrefs = {}
        for (var k in engine.prefs) nextPrefs[k] = engine.prefs[k]
        nextPrefs.updateCheck = false
        engine.prefs = SkinParser.normalizePrefs(nextPrefs)
        persistDebounce.restart()
      }
      engine.notice("status.hookConflict", "post-update.d/barcraft-sync", true)
      finish()
    })
  }

  // A plain-text health report: `omarchy-shell barcraft doctor`.
  function doctor() {
    var layout = barConfig && barConfig.layout ? barConfig.layout : {}
    var placed = false
    for (var section in layout) {
      var list = layout[section] || []
      for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        var id = entry && typeof entry === "object" ? entry.id : entry
        if (id === "thepixelgardener.barcraft") placed = true
      }
    }
    var mons = []
    var seenScreens = {}
    for (var screen in monitorSkins) {
      seenScreens[screen] = true
      var tag = monitorDrafts && monitorDrafts[screen] ? (monitorSkins[screen] + " (edited)") : monitorSkins[screen]
      mons.push(screen + "=" + tag)
    }
    for (var dScreen in monitorDrafts) {
      if (!seenScreens[dScreen]) mons.push(dScreen + "=draft(" + monitorDrafts[dScreen].name + ")")
    }
    var lines = [
      "Barcraft " + (manifest && manifest.version ? manifest.version : "?") + " is the active bar",
      "Studio widget on the bar: " + (placed ? "yes" : "no (omarchy-shell barcraft restoreButton)"),
      "Settings: shell.json bar.barcraft" + (configBlock ? "" : " (not written yet: still the defaults)") + (migrated ? ", moved from barcraft.toml" : ""),
      "Wearing: " + currentName() + " (" + currentId() + ")" + (standard ? ", Omarchy standard on" : ""),
      "Per-monitor skins: " + (mons.length ? mons.join(", ") : "none"),
      "Blur: skin " + (committedBlur ? "wants it" : "doesn't") + ", Omarchy background is " + (barTransparent ? "clear" : (barGlassy ? "glassy" : "opaque")),
      "Icon size: " + Math.round(committedIconScale * 100) + "%" + (Math.abs(committedIconScale - 1) > 0.001 ? " via [bar] tokens in ~/.config/omarchy/shell.toml" : ""),
      "Saved skins: " + userSkins.length + " in " + userSkinsDir
        + (truncatedSkinCount > 0
          ? " (" + (truncatedSkinCount >= 1000 ? "1000+" : truncatedSkinCount) + " more skipped; limit is " + SkinParser.MAX_SCANNED_SKINS + ")"
          : ""),
      "Omarchy menu entries: " + (prefs.omarchyMenu ? "on" : "off") + ", update check hook: " + (prefs.updateCheck ? "on" : "off"),
      "Plugin folder: " + pluginDir,
      "Omarchy bar base: scripts/sync-upstream.sh --check tells whether Omarchy's bar moved"
    ]
    var diagLines = []
    if (themeSkinInspection) {
      for (var te = 0; te < themeSkinInspection.errors.length; te++) {
        diagLines.push("  theme [bar-skin]: " + themeSkinInspection.errors[te].message)
      }
      for (var ta = 0; ta < themeSkinInspection.adjustments.length; ta++) {
        diagLines.push("  theme [bar-skin]: " + themeSkinInspection.adjustments[ta].message)
      }
    }
    for (var d = 0; d < skinDiagnostics.length; d++) {
      var item = skinDiagnostics[d]
      for (var e = 0; e < item.errors.length; e++) {
        diagLines.push("  " + item.path + ": " + item.errors[e].message)
      }
      for (var a = 0; a < item.adjustments.length; a++) {
        diagLines.push("  " + item.path + ": " + item.adjustments[a].message)
      }
    }
    if (diagLines.length > 0) {
      lines.push("Skin diagnostics:")
      for (var dl = 0; dl < diagLines.length; dl++) lines.push(diagLines[dl])
    }
    return lines.join("\n")
  }

  // ---- Icon size: Omarchy's [bar] icon tokens in ~/.config/omarchy/shell.toml

  readonly property real committedIconScale: standard ? 1 : (committedSkin ? Number(committedSkin.iconScale || 1) : 1)
  onCommittedIconScaleChanged: if (isPrimary && settled) iconScaleDebounce.restart()

  Timer {
    id: iconScaleDebounce
    interval: 450
    repeat: false
    onTriggered: engine.applyIconScale()
  }

  function applyIconScale() {
    if (!isPrimary || !settled) return
    if (_iconSyncBusy) {
      _iconSyncAgain = true
      return
    }
    _iconSyncBusy = true
    _iconSyncAgain = false
    var targetScale = committedIconScale
    var reset = Math.abs(targetScale - 1) < 0.001

    store.editSharedFile(userShellTomlPath, function(current) {
      if (reset && current.indexOf("# barcraft") < 0) return null
      return SkinParser.applyBarIconOverrides(current, targetScale)
    }, function() {
      engine._iconSyncBusy = false
      if (engine._iconSyncAgain) Qt.callLater(engine.applyIconScale)
    })
  }

  // A paste into a Studio field (LineField asks rather than reading the
  // clipboard itself): one line of text, bounded in both bytes and time.
  property var _fieldPaste: null

  function pasteInto(field) {
    if (!field || !field.takesPaste || field.readOnly || fieldPasteProc.running) return
    _fieldPaste = { field: field, value: field.text, from: field.selectionStart, to: field.selectionEnd }
    fieldPasteProc.running = true
  }

  Process {
    id: fieldPasteProc
    command: ["sh", "-c", "timeout 2 wl-paste --no-newline --type text 2>/dev/null | head -c 256"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var request = engine._fieldPaste
        engine._fieldPaste = null
        var field = request ? request.field : null
        if (!field || !field.activeFocus || field.text !== request.value
            || field.selectionStart !== request.from || field.selectionEnd !== request.to) return
        field.insertPastedText(text)
      }
    }
  }

  // Clipboard text, bounded in time and cut off just past the 32 KiB a skin may be.
  Process {
    id: pasteProc
    command: ["sh", "-c", "timeout 2 wl-paste --no-newline --type text 2>/dev/null | head -c 32769"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: engine.importText(text, engine._pasteTarget)
    }
  }

  // ---- About & explicit plugin update check --------------------------------

  property string _updatePayload: ""
  property bool _updateStreamDone: false
  property bool _updateProcDone: false
  property int _updateExitCode: -1
  property bool _updateTimedOut: false

  function checkForUpdates() {
    if (updateCheckProc.running) return
    updateState = "checking"
    remoteVersion = ""
    _updateTimedOut = false
    _updatePayload = ""
    _updateStreamDone = false
    _updateProcDone = false
    _updateExitCode = -1
    updateCheckProc.running = true
    updateCheckWatchdog.restart()
  }

  function _finishUpdateCheck() {
    if (_updateTimedOut || !_updateStreamDone || !_updateProcDone) return
    updateCheckWatchdog.stop()
    if (_updateExitCode !== 0) {
      updateState = "error"
      notice("status.updateCheckFailed", "", true)
      return
    }
    var remote = SkinParser.parseRemoteManifestVersion(_updatePayload, "thepixelgardener.barcraft")
    var cmp = remote ? SkinParser.compareSemver(remote, pluginVersion) : null
    if (!remote || cmp === null) {
      updateState = "error"
      notice("status.updateCheckFailed", "", true)
      return
    }
    remoteVersion = remote
    if (cmp > 0) {
      updateState = "available"
      notice("status.updateAvailable", remote, false)
    } else if (cmp === 0) {
      updateState = "uptodate"
      notice("status.updateCurrent", pluginVersion, false)
    } else {
      updateState = "ahead"
      notice("status.updateAhead", pluginVersion, false)
    }
  }

  function requestPluginUpdate() {
    runCommand(["omarchy-launch-floating-terminal-with-presentation", "omarchy plugin update thepixelgardener.barcraft"])
  }

  function openRepository() {
    runCommand(["xdg-open", repositoryUrl])
  }

  function openIssues() {
    runCommand(["xdg-open", issuesUrl])
  }

  Timer {
    id: updateCheckWatchdog
    interval: 8000
    repeat: false
    onTriggered: {
      if (!updateCheckProc.running) return
      engine._updateTimedOut = true
      updateCheckProc.running = false
      engine.updateState = "error"
      engine.notice("status.updateCheckFailed", "", true)
    }
  }

  Process {
    id: updateCheckProc
    command: ["sh", "-c",
      "curl -fsSL --proto =https --proto-redir =https --tlsv1.2 --max-time 6 --max-filesize 16384 \"$1\" 2>/dev/null | head -c 16385",
      "sh", engine.remoteManifestUrl]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        engine._updatePayload = text
        engine._updateStreamDone = true
        engine._finishUpdateCheck()
      }
    }
    onExited: function(code) {
      engine._updateExitCode = code
      engine._updateProcDone = true
      engine._finishUpdateCheck()
    }
  }

  Component.onCompleted: {
    loadTimer.restart()
  }
}
