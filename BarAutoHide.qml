import QtQuick
import Quickshell.Hyprland
import qs.Commons

// Per-screen auto-hide controller and screen-edge hover sensor + accent
// hairline. Kept separate from Bar.qml to minimize upstream sync surface.
Item {
  id: autoHide

  required property var host
  required property var look
  property var screen: null
  property string position: "top"
  property bool vertical: false
  property bool barHidden: false
  property bool dragActive: false
  property bool activePopout: false
  property bool stripHovered: false

  readonly property var engine: host ? host.engine : null
  readonly property bool enabled: !!(look && look.autoHide)
  readonly property int hoverEdgePx: Math.max(2, look ? look.hoverEdgePx : 4)
  readonly property bool accentHairline: !!(look && look.accentHairline)
  readonly property color accentColor: look ? look.resolvedAccent : "white"

  property bool revealed: false

  readonly property var hyprMonitor: screen ? Hyprland.monitorFor(screen) : null
  readonly property int activeWorkspaceId: hyprMonitor && hyprMonitor.activeWorkspace ? hyprMonitor.activeWorkspace.id : -1
  onActiveWorkspaceIdChanged: if (engine && engine.prefs.revealOnWorkspace) peek(1200)
  readonly property bool hasWindows: activeWorkspaceId !== -1 && host
    && host.workspaceHasWindows(Hyprland.toplevels.values, activeWorkspaceId)
  // "Only with windows": an empty workspace keeps the bar out.
  readonly property bool hideAllowed: !engine || engine.prefs.autohideWhen !== "windows" || hasWindows

  readonly property bool effectivelyHidden: barHidden
    || (enabled && hideAllowed && !revealed && !dragActive && !activePopout)

  onStripHoveredChanged: {
    if (!enabled) return
    if (stripHovered) {
      hideDelay.stop()
      peekTimer.stop()
      revealed = true
    } else {
      hideDelay.restart()
    }
  }

  function peek(ms) {
    if (!enabled) return
    hideDelay.stop()
    revealed = true
    peekTimer.interval = ms
    peekTimer.restart()
  }

  Timer {
    id: hideDelay
    interval: autoHide.engine ? autoHide.engine.prefs.autohideDelay : 320
    repeat: false
    onTriggered: autoHide.revealed = false
  }

  // A peek (workspace switch, `omarchy-shell barcraft reveal`) shows the bar
  // for a moment, then lets it tuck away again unless the pointer is on it.
  Timer {
    id: peekTimer
    repeat: false
    onTriggered: if (!autoHide.stripHovered) autoHide.revealed = false
  }

  Connections {
    target: autoHide.host
    function onRevealSerialChanged() { autoHide.peek(2200) }
  }

  // Slim edge sensor + optional accent hairline while auto-hide tucks the bar away.
  visible: enabled && !barHidden
  x: position === "right" ? (parent ? parent.width - hoverEdgePx : 0) : 0
  y: position === "bottom" ? (parent ? parent.height - hoverEdgePx : 0) : 0
  width: vertical ? hoverEdgePx : (parent ? parent.width : 0)
  height: vertical ? (parent ? parent.height : 0) : hoverEdgePx

  Rectangle {
    visible: autoHide.accentHairline && autoHide.effectivelyHidden
    anchors.horizontalCenter: autoHide.vertical ? undefined : parent.horizontalCenter
    anchors.verticalCenter: autoHide.vertical ? parent.verticalCenter : undefined
    anchors.top: autoHide.position === "top" ? parent.top : undefined
    anchors.bottom: autoHide.position === "bottom" ? parent.bottom : undefined
    anchors.left: autoHide.position === "left" ? parent.left : undefined
    anchors.right: autoHide.position === "right" ? parent.right : undefined
    width: autoHide.vertical ? 2 : Math.min(parent.width * 0.24, Style.space(220))
    height: autoHide.vertical ? Math.min(parent.height * 0.24, Style.space(220)) : 2
    radius: 1
    color: autoHide.accentColor
    opacity: 0.72
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onEntered: {
      hideDelay.stop()
      autoHide.revealed = true
    }
  }
}
