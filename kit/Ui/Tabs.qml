import QtQuick
import "../Theme"
import "../Theme" as Commons

// Text tabs over a 1px track rule, the selected one bold with an accent underline that slides
// between tabs. A tab under the pointer or the keyboard cursor takes the hover fill and full
// foreground; the rest are dim. For a small choice inside a form, use ButtonGroup.
//
//   Tabs { model: ["General", "Display", "Audio"]; currentIndex: 0; onActivated: (i) => page = i }
//
// Keyboard (focusable): Left/Right or h/l move the selection, Home/End jump.
FocusScope {
  id: root

  property var model: []
  property int currentIndex: 0
  // Forces the cursor look on one tab (-1: none), for still renders and keyboard models.
  property int cursorIndex: -1

  signal activated(int index)

  function select(i) {
    var n = repeater.count
    if (n === 0) return
    i = Math.max(0, Math.min(n - 1, i))
    if (i === currentIndex) return
    currentIndex = i
    activated(i)
  }

  activeFocusOnTab: true
  implicitWidth: tabRow.implicitWidth
  implicitHeight: tabRow.implicitHeight

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left || event.text === "h") select(currentIndex - 1)
    else if (event.key === Qt.Key_Right || event.text === "l") select(currentIndex + 1)
    else if (event.key === Qt.Key_Home) select(0)
    else if (event.key === Qt.Key_End) select(repeater.count - 1)
    else return
    event.accepted = true
  }

  Rectangle {
    y: root.height - 1
    width: root.width
    height: 1
    color: Commons.Color.track
  }

  Row {
    id: tabRow
    spacing: Style.spacing.xxs

    Repeater {
      id: repeater
      model: root.model
      delegate: Rectangle {
        id: tab
        required property var modelData
        required property int index
        readonly property bool selected: index === root.currentIndex
        readonly property bool hot: mouse.containsMouse || index === root.cursorIndex || (root.activeFocus && selected)

        implicitWidth: Math.ceil(label.implicitWidth) + Style.spacing.controlPaddingX * 2
        implicitHeight: label.implicitHeight + Style.spacing.controlPaddingY * 2
        width: implicitWidth
        height: implicitHeight
        radius: Math.min(4, Style.cornerRadius)
        color: mouse.pressed ? Style.pressedFill : hot ? Style.hoverFill : "transparent"
        Behavior on color { ColorAnimation { duration: Style.duration(120) } }

        Text {
          id: label
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: tab.modelData
          color: tab.selected ? Style.selectedStateColor(Commons.Color.foreground, Commons.Color.accent)
            : tab.hot ? Commons.Color.foreground : Commons.Color.textDim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: tab.selected
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.forceActiveFocus(); root.select(tab.index) }
        }
      }
    }
  }

  Rectangle {
    readonly property Item target: repeater.count > root.currentIndex && root.currentIndex >= 0 ? repeater.itemAt(root.currentIndex) : null
    visible: target !== null
    x: target ? target.x : 0
    y: root.height - height
    width: target ? target.width : 0
    height: Style.spacing.xxs
    color: Commons.Color.accent
    Behavior on x { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
    Behavior on width { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
  }
}
