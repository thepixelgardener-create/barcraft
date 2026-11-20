import QtQuick
import "../Theme"
import "../Theme" as Commons

// One row of a settings list: a label and an optional dim description on the left, any control
// (ToggleSwitch, Dropdown, NumberField, Button...) on the right. Rows stacked in a column line
// their labels and their controls up, so a list of them reads as a form.
//
//   SettingRow { label: "Night light"; description: "Warm the screen after sunset"
//                ToggleSwitch { checked: s.night; onToggled: s.night = !s.night } }
//
// The control keeps its own keyboard and states; `hasCursor` paints the row's hover fill for
// panels that walk rows with a keyboard cursor. Disabled rows dim their words.
Item {
  id: root

  property string label: ""
  property string description: ""
  property bool hasCursor: false
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  default property alias control: trailing.data

  readonly property int _padX: Style.spacing.rowPaddingX
  readonly property int _padY: Style.spacing.md

  implicitWidth: Style.space(240)
  implicitHeight: Math.max(Style.spacing.controlHeight, words.implicitHeight, trailing.implicitHeight) + _padY * 2

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.hasCursor ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
  }

  Column {
    id: words
    anchors.left: parent.left
    anchors.leftMargin: root._padX
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(0, root.width - root._padX * 2 - trailing.width - Style.spacing.xxl)
    spacing: Style.spacing.xxs

    Text {
      textFormat: Text.PlainText
      text: root.label
      color: root.enabled ? root.foreground : Commons.Color.textFaint
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      width: parent.width
    }

    Text {
      textFormat: Text.PlainText
      visible: root.description !== ""
      text: root.description
      color: root.enabled ? Commons.Color.textDim : Commons.Color.textFaint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      width: parent.width
    }
  }

  Row {
    id: trailing
    anchors.right: parent.right
    anchors.rightMargin: root._padX
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.md
  }
}
