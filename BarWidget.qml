import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The Barcraft button. Click opens Barcraft Studio, a keyboard panel, so it
// also opens from a keybinding (`omarchy-shell shell toggle
// thepixelgardener.barcraft`) and takes the keys at once. Right-click steps
// through the theme's skin, the classic presets and saved skins.
BarWidget {
  id: root
  moduleName: "thepixelgardener.barcraft"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property bool panelOpen: false
  property bool popoutSwitchClosing: false
  // The engine of the Barcraft bar this widget sits in, found by walking up
  // to the bar strip (see Bar.qml barcraftEngine). Omarchy loads a bar
  // plugin's widget only while that bar is active, so it is always there
  // once the widget is placed; the local engine only covers the moment
  // before, and must never be what the Studio edits.
  property var hostEngine: null
  readonly property var skinEngine: hostEngine ? hostEngine : localEngineLoader.item

  function locateEngine() {
    for (var p = root.parent; p; p = p.parent) {
      if ("barcraftEngine" in p && p.barcraftEngine) {
        if (hostEngine !== p.barcraftEngine) hostEngine = p.barcraftEngine
        return
      }
    }
  }

  onParentChanged: Qt.callLater(root.locateEngine)

  Loader {
    id: localEngineLoader
    active: !root.hostEngine
    sourceComponent: Component {
      SkinEngine { isPrimary: false }
    }
  }

  // ---- Panel contract the bar routes summon/hide/toggle and Tab through.
  readonly property bool opened: panelOpen

  function open() {
    locateEngine()
    if (skinEngine) skinEngine.rescanUserSkins()
    panelOpen = true
  }

  function close() {
    panelOpen = false
    if (skinEngine) skinEngine.clearPreview()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  // Open on a tab: presets, colors, geometry, surface or behavior.
  property string requestedTab: ""
  property int tabRequest: 0
  function openTab(tab) {
    requestedTab = String(tab || "")
    tabRequest++
    open()
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(root, direction)
    return false
  }

  // Its own id: "strings" would be shadowed by StudioContent's property of
  // the same name, which then read itself and fell back to the key.
  Translations {
    id: barcraftStrings
    directory: Qt.resolvedUrl("i18n")
  }

  // The Studio is drawn with the Omarchy UI kit (kit/); this feeds it the
  // theme the shell draws with.
  KitTheme {}

  Component.onCompleted: Qt.callLater(root.locateEngine)

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The mark is drawn, not a glyph: a slot the size of an icon glyph's.
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Style.bar.iconSlot
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    tooltipText: {
      var eng = root.skinEngine
      if (!eng) return barcraftStrings.t("tooltip").arg("")
      eng.revision
      var name = eng.standard ? barcraftStrings.t("label.standard") : (eng.committedSkin ? eng.committedSkin.name : "")
      return barcraftStrings.t("tooltip").arg(name)
    }
    onPressed: function(mouseButton) {
      root.locateEngine()
      if (mouseButton === Qt.RightButton) {
        if (root.skinEngine) root.skinEngine.cycleSkin()
      } else {
        root.toggle()
      }
    }

    BarcraftMark {
      anchors.centerIn: parent
      ink: button.foreground
      lit: root.panelOpen
      scale: button.pressScale
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.panelOpen
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(450))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: studio.implicitHeight
      blocked: studio.textEditing
      onMoveRequested: function(dx, dy) { studio.navMove(dx, dy) }
      onActivateRequested: function(modifiers) { studio.navActivate() }
      onCloseRequested: root.close()
      onDeleteRequested: studio.navDelete()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text, modifiers) { studio.navText(text) }

      StudioContent {
        id: studio
        width: parent.width
        bar: root.bar
        engine: root.skinEngine
        strings: barcraftStrings
        panelOpen: root.panelOpen
        requestedTab: root.requestedTab
        tabRequest: root.tabRequest
        keyTarget: keyCatcher
        maxHeight: Math.max(Style.space(320), panel.availableCardHeight - panel.verticalContentInset)
      }
    }
  }
}
