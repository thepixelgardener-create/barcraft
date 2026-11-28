import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "BarModel.js" as BarModel

// Barcraft's bar-level host: owns the SkinEngine, first-run Studio button
// placement (working around PluginRegistry.setEnabled's early return for
// dual-kind bar plugins), and the `omarchy-shell barcraft ...` IPC surface.
// Kept out of Bar.qml so upstream Omarchy bar syncs stay small.
Item {
  id: host

  visible: false
  width: 0
  height: 0

  property var shell: null
  property var barConfig: null
  property var manifest: null
  property string omarchyPath: "/usr/share/omarchy"
  property bool glassy: false
  property bool transparent: false
  property bool vertical: false
  // Callback: (pluginId) => panel widget item or null.
  property var findPanelWidgetFn: null

  readonly property alias engine: skin
  // Bumped to peek an auto-hidden bar out on every screen for a moment.
  property int revealSerial: 0

  // Fallback component for our own Studio button: Omarchy r8499's
  // PluginRegistry.inBar() checks findEntryLocation().kind === "bar", which
  // returns "bar-option" first for dual-kind bar + bar-widget plugins and
  // leaves their barWidgetRegistry entry with component: null even when placed
  // in bar.layout.
  // Created once with the host as its parent, so it goes with the host and is
  // never destroyed by hand (the engine may free a parentless one first on a
  // shell reload). Bar.qml's widget binding only reads it, so nothing writes
  // state while that binding evaluates.
  property var studioWidgetComp: null
  Component.onCompleted: {
    var comp = Qt.createComponent(Qt.resolvedUrl("BarWidget.qml"), Component.PreferSynchronous, host)
    function settle() {
      if (comp.status === Component.Ready) host.studioWidgetComp = comp
      else if (comp.status === Component.Error) console.warn("Barcraft: fallback BarWidget load failed: " + comp.errorString())
    }
    if (comp.status === Component.Loading) comp.statusChanged.connect(settle)
    else settle()
  }

  // Omarchy's shipped shell.json, read only when first-run placement finds no
  // bar.layout at all, so the write keeps every stock widget.
  FileView {
    id: stockShellDefaultsFile
    path: (host.omarchyPath || "/usr/share/omarchy") + "/config/omarchy/shell.json"
    preload: false
    blockAllReads: true
    watchChanges: false
    printErrors: false
  }

  // Omarchy's stock layout, or null when it can't be read: placement then
  // writes nothing rather than a layout that drops stock widgets.
  function stockFallbackLayout() {
    var raw = ""
    try {
      raw = String(stockShellDefaultsFile.text() || "").trim()
    } catch (e) {}
    if (!raw) return null
    try {
      var parsed = JSON.parse(raw)
      if (parsed && Util.isPlainObject(parsed.bar) && Util.isPlainObject(parsed.bar.layout)) return parsed.bar.layout
    } catch (e2) {}
    console.warn("Barcraft: could not read Omarchy's stock bar layout from " + stockShellDefaultsFile.path)
    return null
  }

  // Puts the Studio button on the bar when it belongs there (first run, or
  // `force` for restoreButton). Returns "restored" when it was added or moved,
  // "flagged" when only the placed marker was recorded, "present" when nothing
  // needed to change and "error" when shell.json can't be written.
  function ensureStudioButton(force) {
    if (!host.shell || typeof host.shell.mutateShellConfig !== "function") return "error"
    var id = "thepixelgardener.barcraft"
    var options = { force: !!force }
    var fallback = function() { return host.stockFallbackLayout() }
    var probe = { bar: JSON.parse(JSON.stringify(Util.isPlainObject(host.barConfig) ? host.barConfig : {})) }
    var reachableBefore = BarModel.studioButtonPlacement(probe.bar.layout, id).reachable
    if (!BarModel.placeStudioButton(probe, id, fallback, options)) return "present"
    var changed = false
    var ok = host.shell.mutateShellConfig(function(config) {
      if (BarModel.placeStudioButton(config, id, fallback, options)) changed = true
    })
    if (ok === false) return "error"
    if (!changed) return "present"
    skin.studioButtonPlaced = true
    return reachableBefore ? "flagged" : "restored"
  }

  // Whether a workspace holds any window, for auto-hide's "only with windows".
  function workspaceHasWindows(toplevels, workspaceId) {
    var list = toplevels || []
    for (var i = 0; i < list.length; i++) {
      var toplevel = list[i]
      if (toplevel && toplevel.workspace && toplevel.workspace.id === workspaceId) return true
    }
    return false
  }

  SkinEngine {
    id: skin
    barGlassy: host.glassy
    barTransparent: host.transparent
    shellApi: host.shell
    barConfig: host.barConfig
    manifest: host.manifest
    vertical: host.vertical
    ensureStudioButtonFn: function(force) { return host.ensureStudioButton(force) }
  }

  ShellIpc {
    target: "barcraft"

    function ping(): string { return "ok" }
    // The id the bar wears: a skin id, "standard", "theme" or "draft".
    function current(): string { return skin.currentId() }
    function doctor(): string { return skin.doctor() }
    function reveal(): void { host.revealSerial++ }
    // Open the Studio on a tab: presets, colors, geometry, surface, behavior.
    function studio(tab: string): void {
      var item = typeof host.findPanelWidgetFn === "function" ? host.findPanelWidgetFn("thepixelgardener.barcraft") : null
      if (item && typeof item.openTab === "function") item.openTab(tab)
      else skin.notifyMissingStudioButton()
    }
    // Put the Barcraft Studio button back on the bar when removed earlier.
    function restoreButton(): string {
      var result = host.ensureStudioButton(true)
      return result === "flagged" ? "present" : result
    }
    // Changes made here show their result in Omarchy's OSD.
    function toggleAutoHide(): void { skin.toggleAutoHide(); skin.announce() }
    function next(): string { var name = skin.cycleSkin(); skin.announce(); return name }
    function setSkin(id: string): void { if (skin.selectSkin(id)) skin.announce() }
    function followTheme(): void { skin.setFollowTheme(true); skin.announce() }
    // Omarchy's own bar look on or off; skins stay for when it goes off.
    function toggleStandard(): void { skin.setStandard(!skin.standard); skin.announce() }
  }
}
