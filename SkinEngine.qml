import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "SkinParser.js" as SkinParser
import "BarcraftBridge.js" as Bridge

// Barcraft's state: the chosen skin, saved skins, preferences, per-monitor
// skins and the live preview. The bar owns the primary engine; the Studio
// widget borrows it through BarcraftBridge, so an edit shows on the bar at
// once without polling a file.
Item {
  id: engine

  visible: false
  width: 0
  height: 0

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string configDir: homeDir + "/.config/omarchy"
  readonly property string stateFilePath: configDir + "/barcraft.toml"
  readonly property string userSkinsDir: configDir + "/bar-skins"
  readonly property string userShellTomlPath: configDir + "/shell.toml"

  property bool isPrimary: true
  // Told by the bar: Omarchy's own background setting (omarchy-bar background).
  property bool barGlassy: false
  property bool barTransparent: false

  property string activeSkinId: "floating"
  property bool followTheme: true
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

  SkinLook {
    id: mainLook
    skin: engine.activeSkin
    paletteMap: engine.themeColors
    barGlassy: engine.barGlassy
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
  function zoneFor(screenName) {
    var own = monitorSkinFor(screenName) || committedSkin
    return {
      height: committedSkin ? committedSkin.height : 30,
      edgeMargin: own.mode === "edge" ? 0 : own.edgeMargin,
      autoHide: own.visibility === "autohide"
    }
  }

  // The id the Studio marks as chosen for a screen ("" = the main skin).
  function chosenIdFor(screenName) {
    if (screenName) {
      var id = monitorSkins ? monitorSkins[screenName] : undefined
      return id ? String(id) : ""
    }
    if (usingThemeSkin) return "theme"
    return hasCustomDraft ? "" : activeSkinId
  }

  // ---- Choosing ------------------------------------------------------------

  function previewById(id, screenName) {
    var s = id === "theme" ? themeSkin : findSkinById(id)
    if (!s) return
    previewScreen = String(screenName || "")
    previewSkin = s
  }

  function clearPreview() {
    if (previewSkin !== null) previewSkin = null
    previewScreen = ""
  }

  function selectSkin(id) {
    if (id === "theme") {
      setFollowTheme(true)
      return
    }
    var found = findSkinById(id)
    if (!found) return
    clearPreview()
    activeSkinId = found.id
    hasCustomDraft = false
    customSkin = SkinParser.normalizeSkin(found, found.id, found.source)
    if (themeSkin) followTheme = false
    revision++
    persistState()
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
    monitorSkins = next
    revision++
    persistState()
  }

  function setFollowTheme(enabled) {
    clearPreview()
    followTheme = !!enabled
    if (followTheme && themeSkin) hasCustomDraft = false
    revision++
    persistState()
  }

  // Right-click on the widget: the theme's skin, the classic presets and the
  // saved skins, in a ring. Returns the name now on.
  function cycleSkin() {
    var ring = []
    if (themeSkin) ring.push("theme")
    for (var i = 0; i < classicSkins.length; i++) ring.push(classicSkins[i].id)
    for (var j = 0; j < userSkins.length; j++) ring.push(userSkins[j].id)
    if (ring.length === 0) return ""
    var current = usingThemeSkin ? "theme" : activeSkinId
    var idx = ring.indexOf(current)
    var next = ring[(idx + 1) % ring.length]
    selectSkin(next)
    return activeSkin ? activeSkin.name : ""
  }

  // ---- Editing -------------------------------------------------------------

  function updateField(key, value) {
    clearPreview()
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

  readonly property bool committedBlur: !!(committedSkin && committedSkin.blur)
  onCommittedBlurChanged: if (isPrimary && settled) Qt.callLater(engine.syncBlur)

  function syncBlur() {
    if (!isPrimary) return
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
  }

  function resetToPreset() {
    clearPreview()
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

  function saveUserSkin(rawName) {
    var cleanName = SkinParser.sanitizeLabel(rawName, 40)
    if (!cleanName) cleanName = committedSkin.name || "Custom"
    var slug = slugForName(cleanName, "", false)
    var toSave = SkinParser.normalizeSkin(committedSkin, slug, "user")
    toSave.id = slug
    toSave.name = cleanName
    toSave.source = "user"

    writeFile(skinPath(slug), SkinParser.serializeToml(toSave), function(ok) {
      engine.notice(ok ? "status.saved" : "status.saveFailed", slug, !ok)
    })
    replaceUserSkin(slug, toSave)
    clearPreview()
    activeSkinId = slug
    hasCustomDraft = false
    customSkin = toSave
    if (themeSkin) followTheme = false
    revision++
    persistState()
    return slug
  }

  function renameUserSkin(id, rawName) {
    var skin = null
    for (var i = 0; i < userSkins.length; i++) if (userSkins[i].id === id) skin = userSkins[i]
    var cleanName = SkinParser.sanitizeLabel(rawName, 40)
    if (!skin || !cleanName || cleanName === skin.name) return id
    clearPreview()
    var slug = slugForName(cleanName, id, true)
    var renamed = SkinParser.normalizeSkin(skin, slug, "user")
    renamed.id = slug
    renamed.name = cleanName
    renamed.source = "user"
    writeFile(skinPath(slug), SkinParser.serializeToml(renamed), function(ok) {
      if (!ok) {
        engine.notice("status.saveFailed", slug, true)
        return
      }
      if (slug !== id) engine.runCommand(["rm", "-f", "--", engine.skinPath(id)])
      engine.notice("status.renamed", cleanName, false)
    })
    replaceUserSkin(id, renamed)
    if (activeSkinId === id) {
      activeSkinId = slug
      if (!hasCustomDraft) customSkin = renamed
    }
    var mons = {}
    for (var screen in monitorSkins) mons[screen] = monitorSkins[screen] === id ? slug : monitorSkins[screen]
    monitorSkins = mons
    revision++
    persistState()
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
    runCommand(["rm", "-f", "--", skinPath(id)])
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

  function copyActiveToml() {
    runCommand(["wl-copy", "--", exportActiveToml()])
    notice("status.copied", "", false)
  }

  function importFromClipboard() {
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
    customSkin = skin
    hasCustomDraft = true
    revision++
    persistState()
    notice("status.imported", skin.name, false)
  }

  // ---- Files ---------------------------------------------------------------

  property string _lastStateText: ""

  function persistState() {
    persistDebounce.stop()
    var content = SkinParser.serializeStateToml(activeSkinId, followTheme, hasCustomDraft ? customSkin : null, prefs, monitorSkins)
    if (content === _lastStateText) return
    _lastStateText = content
    stateFileView.setText(content)
  }

  function applyStateText(raw) {
    var st = SkinParser.parseStateToml(raw)
    activeSkinId = st.activeSkinId
    followTheme = st.followTheme
    prefs = st.prefs
    monitorSkins = st.monitors
    var draft = SkinParser.parseToml(raw, st.activeSkinId, "custom", function(id) { return engine.findSkinById(id) })
    if (draft) {
      customSkin = draft
      hasCustomDraft = true
    } else {
      hasCustomDraft = false
    }
    revision++
  }

  // Each write gets its own FileView: concurrent writes never cancel each
  // other, and atomic writes never leave a half-written file behind.
  Component {
    id: fileWriter
    FileView {
      atomicWrites: true
      printErrors: false
      watchChanges: false
      preload: false
    }
  }

  function writeFile(filePath, content, done) {
    var fv = fileWriter.createObject(engine, { path: filePath })
    if (!fv) {
      if (done) done(false)
      return
    }
    fv.saved.connect(function() {
      if (done) done(true)
      fv.destroy()
    })
    fv.saveFailed.connect(function(error) {
      console.warn("Barcraft: could not write " + filePath + ": " + FileViewError.toString(error))
      if (done) done(false)
      fv.destroy()
    })
    fv.setText(content)
  }

  // Commands run one after another, never cancelling the one before.
  property var _commandQueue: []

  function runCommand(argv) {
    _commandQueue = _commandQueue.concat([argv])
    if (!commandProc.running) _nextCommand()
  }

  function _nextCommand() {
    if (commandProc.running || _commandQueue.length === 0) return
    commandProc.command = _commandQueue[0]
    _commandQueue = _commandQueue.slice(1)
    commandProc.running = true
  }

  Process {
    id: commandProc
    onExited: Qt.callLater(engine._nextCommand)
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
    }
  }

  FileView {
    id: stateFileView
    path: engine.stateFilePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var raw = text()
      if (raw !== engine._lastStateText) {
        engine._lastStateText = raw
        if (raw && raw.trim()) engine.applyStateText(raw)
      }
      if (!engine.stateLoaded) {
        engine.stateLoaded = true
        settleTimer.restart()
      }
    }
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound && engine.isPrimary) engine.persistState()
      if (!engine.stateLoaded) {
        engine.stateLoaded = true
        settleTimer.restart()
      }
    }
    onFileChanged: reload()
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
    function onBackgroundChanged() { themeColorsView.reload() }
    function onAccentChanged() { themeColorsView.reload() }
  }

  // ---- Icon size: Omarchy's [bar] icon tokens in ~/.config/omarchy/shell.toml

  readonly property real committedIconScale: committedSkin ? Number(committedSkin.iconScale || 1) : 1
  onCommittedIconScaleChanged: if (isPrimary && settled) iconScaleDebounce.restart()

  Timer {
    id: iconScaleDebounce
    interval: 450
    repeat: false
    onTriggered: engine.applyIconScale()
  }

  FileView {
    id: userShellView
    property bool ready: false
    property bool missing: false
    path: engine.isPrimary ? engine.userShellTomlPath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      ready = true
      missing = false
    }
    onLoadFailed: function(error) {
      // Unreadable is not the same as absent: never write over a file we
      // could not read.
      ready = error === FileViewError.FileNotFound
      missing = ready
    }
    onFileChanged: reload()
  }

  function applyIconScale() {
    if (!isPrimary || !settled || !userShellView.ready) return
    var current = userShellView.missing ? "" : userShellView.text()
    var reset = Math.abs(committedIconScale - 1) < 0.001
    if (reset && current.indexOf("# barcraft") < 0) return
    var next = SkinParser.applyBarIconOverrides(current, committedIconScale)
    if (next === current) return
    userShellView.setText(next)
  }

  Process {
    id: scanProc
    command: ["python3", "-c",
      "import glob, json, os, sys; d = sys.argv[1]; out = [];\n"
      + "for p in sorted(glob.glob(os.path.join(d, '*.toml')))[:200]:\n"
      + "  try:\n"
      + "    if os.path.getsize(p) <= 32768:\n"
      + "      out.append({'slug': os.path.splitext(os.path.basename(p))[0], 'text': open(p, encoding='utf-8', errors='replace').read()})\n"
      + "  except OSError:\n"
      + "    pass\n"
      + "print(json.dumps(out))",
      engine.userSkinsDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var rows = JSON.parse(text || "[]")
          var parsed = []
          for (var i = 0; i < rows.length; i++) {
            var slug = SkinParser.slugify(rows[i].slug)
            var skin = SkinParser.parseToml(rows[i].text, slug, "user", function(id) { return engine.findSkinById(id) })
            if (!skin) continue
            skin.id = slug
            skin.source = "user"
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

  // Clipboard text, cut off just past the 32 KiB a skin may be.
  Process {
    id: pasteProc
    command: ["sh", "-c", "wl-paste --no-newline --type text 2>/dev/null | head -c 32769"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: engine.importText(text)
    }
  }

  Component.onCompleted: {
    if (isPrimary) Bridge.registerEngine(engine)
    rescanUserSkins()
  }

  Component.onDestruction: {
    if (isPrimary) Bridge.unregisterEngine(engine)
  }
}
