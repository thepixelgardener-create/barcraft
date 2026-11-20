import QtQuick
import "../Theme"
import "../Theme" as Commons

// A button showing a color: the swatch inset in a bordered well. Pressing it emits `clicked()`
// so the app can open its picker. The cursor is a ring outside the well (as ToggleSwitch draws
// it), since a well under the hover border would only get fainter.
Item {
  id: root

  property color swatch: Commons.Color.accent
  property bool hasCursor: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent

  signal clicked()
  signal hovered(bool isHovered)

  readonly property int wellWidth: Style.space(44)
  readonly property int wellHeight: Style.space(26)
  readonly property int ringPad: Style.spacing.sm
  readonly property int _radius: Math.min(4, Style.cornerRadius)
  readonly property bool _hot: hasCursor || mouse.containsMouse || activeFocus

  activeFocusOnTab: true
  Keys.onSpacePressed: root.clicked()
  Keys.onReturnPressed: root.clicked()
  Keys.onEnterPressed: root.clicked()

  implicitWidth: wellWidth + ringPad * 2
  implicitHeight: wellHeight + ringPad * 2

  BorderSurface {
    anchors.fill: parent
    visible: root._hot
    color: "transparent"
    radius: root._radius
    borderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
  }

  BorderSurface {
    id: well
    x: root.ringPad
    y: root.ringPad
    width: root.wellWidth
    height: root.wellHeight
    radius: root._radius
    color: Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
    scale: mouse.pressed ? 0.97 : 1

    Behavior on scale { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }

    Rectangle {
      readonly property int inset: Border.top(well.borderSpec) + Style.spacing.xxs
      anchors.fill: parent
      anchors.margins: inset
      radius: Math.max(0, well.radius - Style.spacing.xxs)
      color: root.swatch
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: root.clicked()
  }
}
