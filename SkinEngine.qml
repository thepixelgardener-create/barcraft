import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "SkinParser.js" as SkinParser

// Barcraft's state: the chosen skin, saved skins, preferences, per-monitor
// skins and the live preview. The bar owns the primary engine; the Studio
// widget finds it by walking up to the bar strip it sits in, so an edit shows
// on the bar at once.
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

  property bool isPrimary: true
  // Handed in by the bar: the shell's config facade (writes shell.json),
  // the `bar:` subtree it last loaded, the plugin manifest, and orientation.
  property var shellApi: null
  property var barConfig: null
  property var manifest: null
  property bool vertical: false
  // Told by the bar: Omarchy's own background setting (omarchy-bar background).
  property bool barGlassy: false
  property bool barTransparent: false

  property string activeSkinId: "floating"
  property bool followTheme: true
  // Omarchy standard: show Omarchy's own bar look on every screen. Skins,
  // per-monitor choices and drafts stay put for when it goes off again.
  property bool standard: false
  readonly property var builtinSkins: SkinParser.builtinSkins()
  readonly property var classicSkins: builtinSkins.filter(function(s) { return s.category !== "wild" })
  readonly property var wildSkins: builtinSkins.filter(function(s) { return s.category === "wild" })
  property var userSkins: []
  property var customSkin: SkinParser.defaultSkin()
  property bool hasCustomDraft: false
  property var prefs: SkinParser.defaultPrefs()
  // screen name -> skin id ("theme" for the theme's skin).
  property var monitorSkins: ({})
  property int revision: 0
  property bool stateLoaded: false
  // Set a moment after the saved state is in, so loading it never counts as
  // the user changing something (blur sync, icon tokens).
  property bool settled: false

  // A skin shown on the bar while a card is hovered or has the keyboard
  // cursor, without committing to it. "" previews on every screen that has
  // no skin of its own.
  property var previewSkin: null
  property string previewScreen: ""
  readonly property bool previewing: previewSkin !== null

  // The active theme's colors.toml: ordered swatches and key -> hex.
  property var themePalette: []
  property var themeColors: ({})

  // Studio messages: a translation key, its %1, and whether it's an error.
  signal notice(string key, string arg, bool isError)

  readonly property var themeSkin: SkinParser.parseFromShellValues(Commons.Color.shellValues, function(id) { return engine.findSkinById(id) })
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

  // The main skin, flattened for the Studio and the bar's shared bindings.
  readonly property string mode: mainLook.mode
  readonly property string art: mainLook.art
  readonly property bool hasArt: mainLook.hasArt
  readonly property bool themeTint: mainLook.themeTint
  readonly property string bezel: mainLook.bezel
  readonly property real bezelStrength: mainLook.bezelStrength
  readonly property real contrast: mainLook.contrast
  readonly property real surfaceTone: mainLook.surfaceTone
  readonly property string customBackground: mainLook.customBackground
  readonly property string customForeground: mainLook.customForeground
  readonly property string customAccent: mainLook.customAccent
  readonly property string gradientTo: mainLook.gradientTo
  readonly property string fill: mainLook.fill
  readonly property int skinHeight: mainLook.skinHeight
  readonly property int edgeMargin: mainLook.edgeMargin
  readonly property int sideMargin: mainLook.sideMargin
  readonly property int sectionGap: mainLook.sectionGap
  readonly property int innerPadding: mainLook.innerPadding
  readonly property int radius: mainLook.radius
  readonly property real iconScale: mainLook.iconScale
  readonly property real backgroundAlpha: mainLook.backgroundAlpha
  readonly property bool blur: mainLook.blur
  readonly property string borderRole: mainLook.borderRole
  readonly property real borderAlpha: mainLook.borderAlpha
  readonly property int borderWidth: mainLook.borderWidth
  readonly property bool shadow: mainLook.shadow
  readonly property real shadowStrength: mainLook.shadowStrength
  readonly property string widgetStyle: mainLook.widgetStyle
  readonly property string visibilityMode: mainLook.visibilityMode
  readonly property bool autoHide: mainLook.autoHide
  readonly property int hoverEdgePx: mainLook.hoverEdgePx
  readonly property bool accentHairline: mainLook.accentHairline
  readonly property color resolvedAccent: mainLook.resolvedAccent
  readonly property color surfaceColor: mainLook.surfaceColor
  readonly property color effectiveForeground: mainLook.effectiveForeground
  readonly property var surfaceBorderSpec: mainLook.surfaceBorderSpec
  // What the Studio's blur switch shows: whether Hyprland blurs the bar now.
  readonly property bool blurActive: barGlassy

  function resolveColorRef(ref) {
    return mainLook.resolveRef(ref)
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
    var id = monitorSkins ? monitorSkins[String(screenName || "")] : undefined
    if (!id) return null
    if (id === "theme") return themeSkin
    return findSkinById(id)
  }

  function hasMonitorSkin(screenName) {
    return monitorSkinFor(screenName) !== null
  }

  // The skin a screen wears: its own if it has one, else the main skin, with
  // a preview on top while one runs for that screen.
  function skinForScreen(screenName) {
    var name = String(screenName || "")
    var own = monitorSkinFor(name)
    if (previewSkin) {
      if (previewScreen === name) return previewSkin
      if (previewScreen === "" && !own) return previewSkin
    }
    return own || committedSkin
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
    var own = monitorSkinFor(screenName) || committedSkin
    return {
      standard: false,
      sizePx: barSizePxOf(committedSkin),
      edgePx: edgePxOf(own),
      autoHide: own.visibility === "autohide"
    }
  }

  // The id the Studio marks as chosen for a screen ("" = the main skin).
  function chosenIdFor(screenName) {
    if (standard) return "standard"
    if (screenName) {
      var id = monitorSkins ? monitorSkins[screenName] : undefined
      return id ? String(id) : ""
    }
    if (usingThemeSkin) return "theme"
    return hasCustomDraft ? "" : activeSkinId
  }

  // ---- Choosing ------------------------------------------------------------

  function previewById(id, screenName) {
    var s = id === "theme" ? themeSkin : (id === "standard" ? SkinParser.standardSkin() : findSkinById(id))
    if (!s) return
    previewScreen = String(screenName || "")
    previewSkin = s
  }

  function clearPreview() {
    if (previewSkin !== null) previewSkin = null
    previewScreen = ""
  }

  function setStandard(enabled) {
    clearPreview()
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
    standard = false
    activeSkinId = found.id
    hasCustomDraft = false
    customSkin = SkinParser.normalizeSkin(found, found.id, found.source)
    if (themeSkin) followTheme = false
    revision++
    persistState()
    return true
  }

  // Gives one screen its own skin; "" hands it back to the main skin.
  function selectForScreen(screenName, id) {
    var name = String(screenName || "")
    if (!name) {
      selectSkin(id)
      return
    }
    var next = {}
    for (var k in monitorSkins) next[k] = monitorSkins[k]
    if (!id) delete next[name]
    else next[name] = id === "theme" ? "theme" : String(id)
    clearPreview()
    if (id) standard = false
    monitorSkins = next
    revision++
    persistState()
  }

  function setFollowTheme(enabled) {
    clearPreview()
    followTheme = !!enabled
    if (followTheme && themeSkin) standard = false
    if (followTheme && themeSkin) hasCustomDraft = false
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
  function currentName() {
    if (standardActive) return strings.t("label.standard")
    return activeSkin ? activeSkin.name : ""
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

  // ---- Editing -------------------------------------------------------------

  function updateField(key, value) {
    clearPreview()
    standard = false
    var base = committedSkin
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
    customSkin = SkinParser.normalizeSkin(next, next.id, "custom")
    hasCustomDraft = true
    revision++
    persistDebounce.restart()
  }

  function toggleAutoHide() {
    updateField("visibility", committedSkin.visibility === "autohide" ? "always" : "autohide")
  }

  // Blur is Omarchy's Glassy bar: omarchy-bar installs the Hyprland layer
  // rule. The skin remembers the wish; this keeps the bar in step with it.
  function setBlur(enabled) {
    var want = !!enabled
    if (!!committedSkin.blur !== want) updateField("blur", want)
    Qt.callLater(engine.syncBlur)
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

  function resetToPreset() {
    clearPreview()
    standard = false
    hasCustomDraft = false
    var found = findSkinById(activeSkinId)
    customSkin = SkinParser.normalizeSkin(found || SkinParser.defaultSkin(), activeSkinId, "builtin")
    revision++
    persistState()
  }

  // ---- Saved skins ---------------------------------------------------------

  function builtinIdTaken(slug) {
    for (var i = 0; i < builtinSkins.length; i++) if (builtinSkins[i].id === slug) return true
    return slug === "theme" || slug === "theme-skin" || SkinParser.canonicalSkinId(slug) !== slug
  }

  // A file name for a skin: never a built-in's id, and when `unique`, not
  // another saved skin's either.
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

  function saveUserSkin(rawName, forceOverwrite) {
    var cleanName = SkinParser.sanitizeLabel(rawName, 40)
    if (!cleanName) cleanName = committedSkin.name || "Custom"
    var target = SkinParser.resolveSaveTarget(cleanName, userSkins, activeSkinId, builtinIdTaken, !!forceOverwrite)
    if (target.needsConfirm) {
      return { ok: false, needsConfirm: true, slug: target.slug, conflictName: target.conflictName }
    }
    var slug = target.slug
    var dest = skinPath(slug)
    var toSave = SkinParser.normalizeSkin(committedSkin, slug, "user")
    toSave.id = slug
    toSave.name = cleanName
    toSave.source = "user"
    toSave.path = dest

    writeFile(dest, SkinParser.serializeToml(toSave), function(ok, code) {
      if (!ok) {
        engine.notice(code === 2 ? "status.saveExists" : "status.saveFailed", slug, true)
        return
      }
      engine.replaceUserSkin(slug, toSave)
      engine.clearPreview()
      engine.standard = false
      engine.activeSkinId = slug
      engine.hasCustomDraft = false
      engine.customSkin = toSave
      if (engine.themeSkin) engine.followTheme = false
      engine.revision++
      engine.persistState()
      engine.notice("status.saved", slug, false)
    }, { noClobber: !target.overwrite })
    return { ok: true, needsConfirm: false, slug: slug, conflictName: "" }
  }

  function renameUserSkin(id, rawName) {
    var skin = null
    for (var i = 0; i < userSkins.length; i++) if (userSkins[i].id === id) skin = userSkins[i]
    var cleanName = SkinParser.sanitizeLabel(rawName, 40)
    if (!skin || !cleanName || cleanName === skin.name) return id
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

    // Write and byte-verify the replacement file on disk before unlinking the
    // original or committing the new id to state.
    writeFile(renamed.path, SkinParser.serializeToml(renamed), function(ok, code) {
      if (!ok) {
        engine.notice(code === 2 ? "status.saveExists" : "status.saveFailed", slug, true)
        return
      }
      engine.replaceUserSkin(id, renamed)
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
      engine.notice("status.renamed", cleanName, false)
    }, { noClobber: !sameFile, removeAfter: removeOld })
    return slug
  }

  function deleteUserSkin(id) {
    var victim = null
    var kept = []
    for (var i = 0; i < userSkins.length; i++) {
      if (userSkins[i].id === id) victim = userSkins[i]
      else kept.push(userSkins[i])
    }
    if (!victim) return
    clearPreview()
    var victimPath = victim.path || skinPath(id)
    if (SkinParser.isSafeSkinPath(victimPath, [userSkinsDir, legacySkinsDir])) {
      runCommand(["rm", "-f", "--", victimPath])
    }
    // The bar doesn't change under you: a deleted skin that's on stays on as
    // an unsaved draft until something else is picked.
    if (activeSkinId === id && !hasCustomDraft && !usingThemeSkin) {
      customSkin = SkinParser.normalizeSkin(victim, id, "custom")
      hasCustomDraft = true
    }
    userSkins = kept
    var mons = {}
    for (var screen in monitorSkins) if (monitorSkins[screen] !== id) mons[screen] = monitorSkins[screen]
    monitorSkins = mons
    revision++
    persistState()
    notice("status.deleted", victim.name, false)
  }

  // ---- Clipboard -----------------------------------------------------------

  function exportActiveToml() {
    return SkinParser.serializeToml(committedSkin)
  }

  // The TOML goes to wl-copy over stdin, never as an argument.
  function copyActiveToml() {
    runJob(["wl-copy"], exportActiveToml(), function(code) {
      if (code === 0) engine.notice("status.copied", "", false)
      else engine.notice("status.copyFailed", "", true)
    })
  }

  function importFromClipboard() {
    if (pasteProc.running) return
    pasteProc.running = true
  }

  function importText(text) {
    var raw = String(text || "")
    if (raw.length > 32768) {
      notice("status.importTooLarge", "", true)
      return
    }
    var skin = SkinParser.parseToml(raw, "imported", "custom", function(id) { return engine.findSkinById(id) })
    if (!skin) {
      notice("status.importFailed", "", true)
      return
    }
    clearPreview()
    standard = false
    customSkin = skin
    hasCustomDraft = true
    revision++
    persistState()
    notice("status.imported", skin.name, false)
  }

  // ---- Settings: shell.json `bar.barcraft` ---------------------------------
  //
  // Omarchy keeps feature settings in shell.json subtrees (bar:, dock:, idle:)
  // and the host writes the file; the bar is handed the `bar:` subtree as
  // barConfig. Barcraft's state is `bar.barcraft` beside position, background
  // and layout, so it moves with the rest of the Omarchy config, `omarchy bar
  // reset` resets it too, and jq reads it.

  readonly property var configBlock: barConfig && typeof barConfig === "object"
    && barConfig.barcraft && typeof barConfig.barcraft === "object" ? barConfig.barcraft : null
  property string _lastConfigJson: ""
  property bool migrated: false

  onConfigBlockChanged: if (stateLoaded) Qt.callLater(engine.applyConfigBlock)

  function stateJson() {
    return JSON.stringify(SkinParser.stateToJson(activeSkinId, followTheme, hasCustomDraft ? customSkin : null, prefs, monitorSkins, standard))
  }

  function persistState() {
    persistDebounce.stop()
    if (!isPrimary || !shellApi || typeof shellApi.mutateShellConfig !== "function") return
    var json = stateJson()
    if (json === _lastConfigJson) return
    _lastConfigJson = json
    shellApi.mutateShellConfig(function(config) {
      if (!config.bar || typeof config.bar !== "object") config.bar = {}
      config.bar.barcraft = JSON.parse(json)
    })
  }

  function applyState(st) {
    activeSkinId = st.activeSkinId
    followTheme = st.followTheme
    standard = !!st.standard
    prefs = st.prefs
    monitorSkins = st.monitors
    if (st.draft) {
      customSkin = st.draft
      hasCustomDraft = true
    } else {
      hasCustomDraft = false
    }
    revision++
  }

  function applyConfigBlock() {
    var block = configBlock
    if (!block) return
    var st = SkinParser.stateFromJson(block, function(id) { return engine.findSkinById(id) })
    var json = JSON.stringify(SkinParser.stateToJson(st.activeSkinId, st.followTheme, st.draft, st.prefs, st.monitors, st.standard))
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
    } else if (isPrimary && legacyStateView.loaded) {
      var raw = legacyStateView.text()
      if (raw && raw.trim()) {
        applyLegacyText(raw)
        persistState()
        migrated = true
        runCommand(["mv", "-n", "--", legacyStatePath, legacyStatePath + ".migrated"])
      }
    }
    stateLoaded = true
    settleTimer.restart()
  }

  FileView {
    id: legacyStateView
    property bool loaded: false
    path: engine.isPrimary ? engine.legacyStatePath : ""
    printErrors: false
    watchChanges: false
    onLoaded: loaded = true
  }

  // The host hands barConfig in right after the bar is built; give it and
  // the legacy file a moment, then settle on whichever holds the state.
  Timer {
    id: loadTimer
    interval: 400
    repeat: false
    onTriggered: engine.loadState()
  }

  // One short shell job with its own watchdog. `input`, when set, goes in over
  // stdin and never onto the command line: other accounts can read command
  // lines, and Quickshell logs a command that fails to start.
  Component {
    id: pipeJob
    Item {
      id: job
      visible: false
      property var command: []
      property var input: null
      property var callback: null
      property bool finished: false
      function start() {
        proc.running = true
        watchdog.start()
      }
      function finish(code) {
        if (finished) return
        finished = true
        watchdog.stop()
        if (callback) callback(code)
        destroy()
      }
      Timer {
        id: watchdog
        interval: 8000
        repeat: false
        onTriggered: {
          proc.running = false
          job.finish(-1)
        }
      }
      Process {
        id: proc
        command: job.command
        stdinEnabled: job.input !== null
        onStarted: {
          if (job.input === null) return
          write(String(job.input))
          stdinEnabled = false
        }
        onExited: function(code, status) { job.finish(code) }
      }
    }
  }

  // done(code): the job's exit code, or -1 when it could not run in time.
  function runJob(argv, input, done) {
    var job = pipeJob.createObject(engine, {
      command: argv,
      input: input === undefined ? null : input,
      callback: done || null
    })
    if (!job) {
      if (done) done(-1)
      return
    }
    job.start()
  }

  // Atomic write that never trusts FileView's `saved` signal. The content goes
  // in over stdin, lands in a temp file beside the target, and must match its
  // MD5 before it replaces the target: by rename, or by hard link when the
  // target may not exist yet. The target keeps its permissions. With
  // `expect`, the target is replaced only while it still has that MD5
  // ("missing": only while it still doesn't exist), checked right before the
  // rename, so a save another program made after Barcraft read the file is
  // never thrown away. Codes for done(ok, code): 0 written, 1 failed,
  // 2 target exists (noClobber), 3 target changed since it was read (expect).
  function writeFile(filePath, content, done, options) {
    var opts = options || {}
    var text = String(content === undefined || content === null ? "" : content)
    var script =
      "dest=$1; want=$2; noclobber=$3; mkexec=$4; old=$5; expect=$6; " +
      "md5() { md5sum | cut -d' ' -f1; }; " +
      "[ -n \"$dest\" ] && [ ! -L \"$dest\" ] || exit 1; " +
      "if [ \"$noclobber\" = 1 ] && [ -e \"$dest\" ]; then exit 2; fi; " +
      "dir=$(dirname -- \"$dest\"); " +
      "mkdir -p -- \"$dir\" || exit 1; " +
      "tmp=$(mktemp \"$dir/.barcraft.XXXXXX\") || exit 1; " +
      "trap 'rm -f -- \"$tmp\"' EXIT; " +
      "cat > \"$tmp\" || exit 1; " +
      "[ \"$(md5 < \"$tmp\")\" = \"$want\" ] || exit 1; " +
      "if [ -f \"$dest\" ]; then chmod --reference=\"$dest\" -- \"$tmp\" || exit 1; " +
      "else m=$(umask); chmod \"$(printf '%o' $(( 0666 & ~m )))\" -- \"$tmp\" || exit 1; fi; " +
      "if [ \"$mkexec\" = 1 ]; then chmod 0755 -- \"$tmp\" || exit 1; fi; " +
      "if [ \"$expect\" = missing ]; then ln -- \"$tmp\" \"$dest\" 2>/dev/null || exit 3; " +
      "elif [ \"$noclobber\" = 1 ]; then ln -- \"$tmp\" \"$dest\" 2>/dev/null || exit 2; " +
      "else " +
      "  if [ -n \"$expect\" ]; then " +
      "    [ ! -L \"$dest\" ] && [ -f \"$dest\" ] && [ \"$(md5 < \"$dest\")\" = \"$expect\" ] || exit 3; " +
      "  fi; " +
      "  mv -f -- \"$tmp\" \"$dest\" || exit 1; " +
      "fi; " +
      "rm -f -- \"$tmp\"; trap - EXIT; " +
      "[ ! -L \"$dest\" ] && [ -f \"$dest\" ] && [ \"$(md5 < \"$dest\")\" = \"$want\" ] || exit 1; " +
      "if [ -n \"$old\" ] && [ \"$old\" != \"$dest\" ] && [ ! -L \"$old\" ] && [ -f \"$old\" ]; then " +
      "  rm -f -- \"$old\" || true; " +
      "fi"
    runJob(["sh", "-c", script, "sh", String(filePath || ""), Qt.md5(text),
            opts.noClobber ? "1" : "0", opts.chmodExec ? "1" : "0",
            String(opts.removeAfter || ""), String(opts.expect || "")],
      text,
      function(code) {
        if (code !== 0 && code !== 3) console.warn("Barcraft: could not write " + filePath + " (code " + code + ")")
        if (done) done(code === 0, code)
      })
  }

  // Removes a regular file only while it still has the MD5 Barcraft checked.
  function removeFileIfUnchanged(filePath, expect, done) {
    var script =
      "p=$1; h=$2; " +
      "[ ! -L \"$p\" ] && [ -f \"$p\" ] && [ \"$(md5sum < \"$p\" | cut -d' ' -f1)\" = \"$h\" ] || exit 3; " +
      "rm -f -- \"$p\""
    runJob(["sh", "-c", script, "sh", String(filePath || ""), String(expect || "")], null, function(code) {
      if (done) done(code === 0, code)
    })
  }

  // Read-modify-write for a file other programs edit too. Reads it fresh,
  // lets `change(current, missing)` return the new text (or null to leave it),
  // and writes only if nobody saved the file in between; otherwise it starts
  // over, at most three times. done(ok)
  function editSharedFile(filePath, change, done, attempt) {
    var tries = attempt || 0
    readTextFile(filePath, function(status, text) {
      if (status === "error") {
        if (done) done(false)
        return
      }
      var missing = status === "missing"
      var current = missing ? "" : text
      var next = change(current, missing)
      if (next === null || next === undefined || next === current) {
        if (done) done(true)
        return
      }
      engine.writeFile(filePath, next, function(ok, code) {
        if (code === 3 && tries < 2) {
          engine.editSharedFile(filePath, change, done, tries + 1)
          return
        }
        if (code === 3) console.warn("Barcraft: " + filePath + " kept changing while Barcraft updated it; left it as it is")
        if (done) done(ok)
      }, { expect: missing ? "missing" : Qt.md5(current) })
    })
  }

  // Fresh, uncached read of a regular non-symlink file from disk.
  // Calls done(status, text) with status "ok" | "missing" | "error".
  Component {
    id: freshReadProc
    Item {
      id: reader
      visible: false
      property var command: []
      property var callback: null
      property bool finished: false
      property string captured: ""
      property bool streamDone: false
      property bool procExited: false
      property int exitCode: -1

      function start() {
        proc.running = true
        watchdog.start()
      }

      function maybeFinish() {
        if (finished || !streamDone || !procExited) return
        finished = true
        watchdog.stop()
        var st = exitCode === 0 ? "ok" : (exitCode === 3 ? "missing" : "error")
        if (callback) callback(st, st === "ok" ? captured : "")
        destroy()
      }

      Timer {
        id: watchdog
        interval: 8000
        repeat: false
        onTriggered: {
          if (reader.finished) return
          reader.finished = true
          proc.running = false
          if (reader.callback) reader.callback("error", "")
          reader.destroy()
        }
      }

      Process {
        id: proc
        command: reader.command
        stdout: StdioCollector {
          waitForEnd: true
          onStreamFinished: {
            reader.captured = text
            reader.streamDone = true
            reader.maybeFinish()
          }
        }
        onExited: function(code, status) {
          reader.exitCode = code
          reader.procExited = true
          reader.maybeFinish()
        }
      }
    }
  }

  function readTextFile(filePath, done) {
    var script =
      "p=$1; " +
      "[ -n \"$p\" ] || exit 4; " +
      "if [ ! -e \"$p\" ] && [ ! -L \"$p\" ]; then exit 3; fi; " +
      "[ ! -L \"$p\" ] && [ -f \"$p\" ] && [ -r \"$p\" ] || exit 4; " +
      "cat -- \"$p\""
    var job = freshReadProc.createObject(engine, {
      command: ["sh", "-c", script, "sh", String(filePath || "")],
      callback: done
    })
    if (!job) {
      if (done) done("error", "")
      return
    }
    job.start()
  }

  // Commands run one after another, never cancelling the one before.
  // Queue depth and runtime are bounded so a stalled external command cannot
  // grow the queue without limit or wedge later bar/OSD operations.
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
    scanProc.running = true
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

  // Appearance → Menu Bar → Barcraft in Omarchy's menu, written into the
  // user's menu extensions between Barcraft's markers. Checkmarks ask the
  // running bar (`omarchy-shell barcraft current`), so they stay true.
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

  // After an Omarchy update: has Omarchy's bar moved under Barcraft's copy?
  // Notify-only; merging stays a deliberate step (scripts/sync-upstream.sh).
  function updateHookCommands() {
    return [
      "plugin=" + shellQuoteSingle(pluginDir),
      "[[ -f $plugin/scripts/sync-upstream.sh ]] || exit 0",
      "if ! bash \"$plugin/scripts/sync-upstream.sh\" --check >/dev/null 2>&1; then",
      "  omarchy-notification-send -g " + shellQuoteSingle("󰍜") + " Barcraft " + shellQuoteSingle(strings.t("hook.changed")),
      "fi",
      ""
    ]
  }

  // Header, then a digest of the rest: Barcraft only ever replaces or removes
  // a hook whose digest still matches, so an edited copy is left alone.
  function updateHookScript() {
    var body = ["# Turn \"Check after Omarchy updates\" off in Barcraft Studio to remove this file."]
      .concat(updateHookCommands()).join("\n")
    return SkinParser.stampUpdateHook(body, Qt.md5)
  }

  // Exactly what 0.5.0 and 0.5.1 wrote here, so an untouched older hook is
  // still recognised as Barcraft's; anything else in that file is left alone.
  function legacyUpdateHookScripts() {
    var commands = updateHookCommands()
    return [
      ["#!/bin/bash",
       "# Added by Barcraft (thepixelgardener.barcraft). Turn \"Check after Omarchy",
       "# updates\" off in Barcraft Studio to remove this file."].concat(commands).join("\n"),
      ["#!/bin/bash",
       SkinParser.HOOK_OWNED_MARKER,
       "# Turn \"Check after Omarchy updates\" off in Barcraft Studio to remove this file."].concat(commands).join("\n")
    ]
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

  // The menu file is shared: read it fresh, change only Barcraft's block, and
  // write it back only if nobody else saved it in between (editSharedFile).
  function syncMenu() {
    if (!isPrimary || !settled) return
    if (_menuSyncBusy) {
      _menuSyncAgain = true
      return
    }
    _menuSyncBusy = true
    _menuSyncAgain = false
    var want = !!prefs.omarchyMenu

    editSharedFile(menuExtensionPath, function(current) {
      if (!want && current.indexOf("barcraft:begin") < 0) return null
      return SkinParser.applyMenuBlock(current, want ? engine.menuEntries() : null)
    }, function() {
      engine._menuSyncBusy = false
      if (engine._menuSyncAgain) Qt.callLater(engine.syncMenu)
    })
  }

  // post-update.d/barcraft-sync is replaced or removed only while it is
  // exactly what Barcraft wrote (isPristineUpdateHook), and only if it is
  // still unchanged at that moment. Anything else in its place is left alone.
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

    readTextFile(updateHookPath, function(status, text) {
      if (status === "missing") {
        if (!want) {
          finish()
          return
        }
        engine.writeFile(engine.updateHookPath, engine.updateHookScript(), function() { finish() },
          { expect: "missing", chmodExec: true })
        return
      }

      var pristine = status === "ok"
        && SkinParser.isPristineUpdateHook(text, Qt.md5, engine.legacyUpdateHookScripts())
      if (pristine && !want) {
        engine.removeFileIfUnchanged(engine.updateHookPath, Qt.md5(text), function() { finish() })
        return
      }
      if (pristine) {
        var desired = engine.updateHookScript()
        if (text === desired) {
          finish()
          return
        }
        engine.writeFile(engine.updateHookPath, desired, function() { finish() },
          { expect: Qt.md5(text), chmodExec: true })
        return
      }
      if (!want) {
        finish()
        return
      }

      // Unreadable, a symlink, somebody else's, or edited since Barcraft wrote
      // it: leave it untouched and turn the toggle back off to match.
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
    for (var screen in monitorSkins) mons.push(screen + "=" + monitorSkins[screen])
    var lines = [
      "Barcraft " + (manifest && manifest.version ? manifest.version : "?") + " is the active bar",
      "Studio widget on the bar: " + (placed ? "yes" : "no (omarchy bar put thepixelgardener.barcraft --section right)"),
      "Settings: shell.json bar.barcraft" + (configBlock ? "" : " (not written yet: still the defaults)") + (migrated ? ", moved from barcraft.toml" : ""),
      "Wearing: " + currentName() + " (" + currentId() + ")" + (standard ? ", Omarchy standard on" : ""),
      "Per-monitor skins: " + (mons.length ? mons.join(", ") : "none"),
      "Blur: skin " + (committedBlur ? "wants it" : "doesn't") + ", Omarchy background is " + (barTransparent ? "clear" : (barGlassy ? "glassy" : "opaque")),
      "Icon size: " + Math.round(committedIconScale * 100) + "%" + (Math.abs(committedIconScale - 1) > 0.001 ? " via [bar] tokens in ~/.config/omarchy/shell.toml" : ""),
      "Saved skins: " + userSkins.length + " in " + userSkinsDir,
      "Omarchy menu entries: " + (prefs.omarchyMenu ? "on" : "off") + ", update check hook: " + (prefs.updateCheck ? "on" : "off"),
      "Omarchy bar base: scripts/sync-upstream.sh --check tells whether Omarchy's bar moved"
    ]
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

    editSharedFile(userShellTomlPath, function(current) {
      if (reset && current.indexOf("# barcraft") < 0) return null
      return SkinParser.applyBarIconOverrides(current, targetScale)
    }, function() {
      engine._iconSyncBusy = false
      if (engine._iconSyncAgain) Qt.callLater(engine.applyIconScale)
    })
  }

  // Saved skins from both folders (the current one first, so it wins a name
  // clash), read with jq like Omarchy's own scripts: no python needed.
  // Rejects symlinks so `stat -c %s` cannot be bypassed by a tiny symlink to a
  // huge file, and caps the file count before buffering into jq -s.
  Process {
    id: scanProc
    command: ["sh", "-c",
      "n=0; for d in \"$@\"; do for f in \"$d\"/*.toml; do "
      + "[ ! -L \"$f\" ] && [ -f \"$f\" ] || continue; "
      + "size=$(stat -c %s \"$f\" 2>/dev/null || echo 999999); "
      + "[ \"$size\" -le 32768 ] || continue; "
      + "jq -Rs --arg path \"$f\" '{path: $path, text: .}' \"$f\"; "
      + "n=$((n + 1)); [ \"$n\" -ge 200 ] && break 2; "
      + "done; done | jq -s '.'",
      "sh", engine.userSkinsDir, engine.legacySkinsDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var rows = JSON.parse(text || "[]")
          var parsed = []
          var seen = Object.create(null)
          var allowed = [engine.userSkinsDir, engine.legacySkinsDir]
          for (var i = 0; i < rows.length; i++) {
            var file = String(rows[i].path || "")
            if (!SkinParser.isSafeSkinPath(file, allowed)) continue
            var slug = SkinParser.slugify(file.replace(/^.*\//, "").replace(/\.toml$/, ""))
            if (seen[slug]) continue
            var skin = SkinParser.parseToml(rows[i].text, slug, "user", function(id) { return engine.findSkinById(id) })
            if (!skin) continue
            seen[slug] = true
            skin.id = slug
            skin.source = "user"
            skin.path = file
            skin.category = skin.art !== "none" ? "wild" : "classic"
            parsed.push(skin)
          }
          engine.userSkins = parsed
          engine.revision++
        } catch (e) {
          console.warn("Barcraft: could not read saved skins: " + e)
        }
      }
    }
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
      onStreamFinished: engine.importText(text)
    }
  }

  Component.onCompleted: {
    rescanUserSkins()
    loadTimer.restart()
  }
}
