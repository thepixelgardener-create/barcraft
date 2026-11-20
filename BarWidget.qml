import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "BarcraftBridge.js" as Bridge

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
  property var bridgedEngine: Bridge.engine()
  // The Barcraft bar's engine. Only a widget placed on another bar plugin
  // builds one of its own.
  readonly property var skinEngine: bridgedEngine ? bridgedEngine : localEngineLoader.item

  Loader {
    id: localEngineLoader
    active: !root.bridgedEngine
    sourceComponent: Component {
      SkinEngine { isPrimary: false }
    }
  }

  // ---- Panel contract the bar routes summon/hide/toggle and Tab through.
  readonly property bool opened: panelOpen

  function open() {
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

  Component.onCompleted: {
    Bridge.subscribe(root._onEngineChanged)
    root.bridgedEngine = Bridge.engine()
  }

  Component.onDestruction: {
    Bridge.unsubscribe(root._onEngineChanged)
  }

  function _onEngineChanged(eng) {
    root.bridgedEngine = eng
  }

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
      var name = eng && eng.committedSkin ? eng.committedSkin.name : ""
      return barcraftStrings.t("tooltip").arg(name)
    }
    onPressed: function(mouseButton) {
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
        keyTarget: keyCatcher
        maxHeight: Math.max(Style.space(320), panel.availableCardHeight - panel.verticalContentInset)
      }
    }
  }
}
