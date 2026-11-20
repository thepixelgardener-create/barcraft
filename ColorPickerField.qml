import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Palette + HSV picker for the Studio's Colors section. A theme swatch picks
// a live reference ("theme.blue") that follows theme switches; the creative
// swatches and the picker pick a fixed "#rrggbb". "" means automatic.
Column {
  id: root

  property color foreground: Commons.Color.popups.text
  property color dimForeground: Qt.darker(Commons.Color.popups.text, 1.45)
  property string currentValue: ""
  // What currentValue looks like now (resolved by the engine).
  property color resolvedColor: fallbackColor
  property color fallbackColor: Commons.Color.bar.background
  property var themePalette: [] // [{ name, key, hex }] from the active colors.toml
  property string resetLabel: "Theme"
  property var strings: null
  property bool pickerExpanded: false
  property string hoveredLabel: ""

  signal colorPicked(string value)

  spacing: Style.spacing.sm

  property real hue: 0.58
  property real sat: 0.65
  property real val: 0.82

  function t(key, fallback) {
    return strings ? strings.t(key) : fallback
  }

  readonly property color shownColor: currentValue !== "" ? resolvedColor : fallbackColor
  readonly property bool isThemeRef: currentValue.indexOf("theme.") === 0

  function toHex2(n) {
    var v = Math.max(0, Math.min(255, Math.round(n)))
    var s = v.toString(16)
    return s.length === 1 ? "0" + s : s
  }

  function colorToHex(c) {
    if (!c) return "#101315"
    return "#" + toHex2(c.r * 255) + toHex2(c.g * 255) + toHex2(c.b * 255)
  }

  function hsvToHex(h, s, v) {
    return colorToHex(Qt.hsva(Math.max(0, Math.min(0.9999, h)), Math.max(0, Math.min(1, s)), Math.max(0, Math.min(1, v)), 1))
  }

  function syncHsvFromColor(c) {
    if (!c) return
    var r = c.r, g = c.g, b = c.b
    var max = Math.max(r, g, b)
    var min = Math.min(r, g, b)
    var d = max - min
    var h = hue
    if (d > 0.0001) {
      if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6
      else if (max === g) h = ((b - r) / d + 2) / 6
      else h = ((r - g) / d + 4) / 6
    }
    hue = h
    sat = max > 0.0001 ? d / max : 0
    val = max
  }

  onCurrentValueChanged: syncHsvFromColor(shownColor)
  Component.onCompleted: syncHsvFromColor(shownColor)

  readonly property var curatedSwatches: [
    "#111318", "#1c1f2b", "#1e1628", "#102421", "#2a1419", "#241d15",
    "#d93829", "#f28b30", "#d4a234", "#34c785", "#2ea8d9", "#4f7cff",
    "#9b6dff", "#e35ca8", "#dce3ec"
  ]

  readonly property var themeSwatches: {
    if (themePalette && themePalette.length > 0) return themePalette
    return [
      { name: "background", key: "background", hex: colorToHex(Commons.Color.background) },
      { name: "accent", key: "accent", hex: colorToHex(Commons.Color.accent) },
      { name: "foreground", key: "foreground", hex: colorToHex(Commons.Color.foreground) }
    ]
  }

  // Left/Right from the keyboard: automatic, then each theme swatch.
  function stepSwatch(direction) {
    var ring = [""]
    for (var i = 0; i < themeSwatches.length; i++) ring.push("theme." + themeSwatches[i].key)
    var idx = ring.indexOf(currentValue)
    var next = idx < 0 ? (direction > 0 ? 1 : ring.length - 1) : (idx + direction + ring.length) % ring.length
    colorPicked(ring[next])
  }

  function valueLabel() {
    if (currentValue === "") return resetLabel
    if (isThemeRef) return t("color.themeRef", "Theme %1").arg(currentValue.slice(6).replace(/_/g, " "))
    return currentValue.toUpperCase()
  }

  // Current value, reset, and the picker toggle.
  RowLayout {
    width: parent.width
    spacing: Style.spacing.sm

    Rectangle {
      Layout.preferredWidth: Style.space(22)
      Layout.preferredHeight: Style.space(22)
      radius: Style.space(6)
      color: root.shownColor
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
    }

    Text {
      textFormat: Text.PlainText
      text: root.hoveredLabel !== "" ? root.hoveredLabel : root.valueLabel()
      color: root.hoveredLabel !== "" || root.currentValue !== "" ? root.foreground : root.dimForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    Button {
      text: root.resetLabel
      selected: root.currentValue === ""
      bordered: true
      onClicked: root.colorPicked("")
    }

    Button {
      text: root.pickerExpanded ? root.t("color.hide", "Hide") : root.t("color.custom", "Custom")
      iconText: "󰌁"
      selected: root.pickerExpanded
      bordered: true
      onClicked: root.pickerExpanded = !root.pickerExpanded
    }
  }

  // The active theme's palette, as live references.
  Column {
    width: parent.width
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      text: root.t("color.themePalette", "Theme palette · follows theme switches")
      color: root.dimForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Flow {
      width: parent.width
      spacing: Style.space(5)

      Repeater {
        model: root.themeSwatches
        Rectangle {
          required property var modelData
          readonly property string hex: String(modelData.hex || "")
          readonly property string ref: "theme." + String(modelData.key || "")
          readonly property bool isChosen: root.currentValue === ref

          width: Style.space(20)
          height: Style.space(20)
          radius: Style.space(5)
          color: hex ? Qt.color(hex) : "transparent"
          border.width: isChosen ? 2 : 1
          border.color: isChosen ? Commons.Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.32)

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hoveredLabel = modelData.name + " · " + parent.hex.toUpperCase()
            onExited: root.hoveredLabel = ""
            onClicked: root.colorPicked(parent.ref)
          }
        }
      }
    }
  }

  // Fixed colors, the same under every theme.
  Column {
    width: parent.width
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      text: root.t("color.creativePalette", "Fixed colors")
      color: root.dimForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Flow {
      width: parent.width
      spacing: Style.space(5)

      Repeater {
        model: root.curatedSwatches
        Rectangle {
          required property string modelData
          readonly property bool isChosen: root.currentValue === modelData

          width: Style.space(20)
          height: Style.space(20)
          radius: Style.space(5)
          color: modelData
          border.width: isChosen ? 2 : 1
          border.color: isChosen ? Commons.Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hoveredLabel = modelData.toUpperCase()
            onExited: root.hoveredLabel = ""
            onClicked: root.colorPicked(modelData)
          }
        }
      }
    }
  }

  // Saturation (x) by value (y) pad, and the hue rainbow.
  Column {
    visible: root.pickerExpanded
    width: parent.width
    spacing: Style.space(8)

    Item {
      id: svPad
      width: parent.width
      height: Style.space(104)

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Qt.hsva(root.hue, 1, 1, 1)
        clip: true

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "#000000" }
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
      }

      Rectangle {
        x: Math.round(root.sat * svPad.width) - width / 2
        y: Math.round((1 - root.val) * svPad.height) - height / 2
        width: Style.space(12)
        height: Style.space(12)
        radius: width / 2
        color: root.shownColor
        border.width: 2
        border.color: "#ffffff"
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        function pickAt(mx, my) {
          root.sat = Math.max(0, Math.min(1, mx / Math.max(1, svPad.width)))
          root.val = Math.max(0, Math.min(1, 1 - my / Math.max(1, svPad.height)))
          root.colorPicked(root.hsvToHex(root.hue, root.sat, root.val))
        }
        onPressed: function(e) { pickAt(e.x, e.y) }
        onPositionChanged: function(e) { if (pressed) pickAt(e.x, e.y) }
      }
    }

    Item {
      id: hueBar
      width: parent.width
      height: Style.space(14)

      Rectangle {
        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.00; color: "#ff0000" }
          GradientStop { position: 0.17; color: "#ffff00" }
          GradientStop { position: 0.33; color: "#00ff00" }
          GradientStop { position: 0.50; color: "#00ffff" }
          GradientStop { position: 0.67; color: "#0000ff" }
          GradientStop { position: 0.83; color: "#ff00ff" }
          GradientStop { position: 1.00; color: "#ff0000" }
        }
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
      }

      Rectangle {
        x: Math.round(root.hue * (hueBar.width - width))
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(10)
        height: Style.space(16)
        radius: Style.space(4)
        color: Qt.hsva(root.hue, 1, 1, 1)
        border.width: 2
        border.color: "#ffffff"
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function pickHue(mx) {
          root.hue = Math.max(0, Math.min(0.9999, mx / Math.max(1, hueBar.width)))
          root.colorPicked(root.hsvToHex(root.hue, root.sat, root.val))
        }
        onPressed: function(e) { pickHue(e.x) }
        onPositionChanged: function(e) { if (pressed) pickHue(e.x) }
      }
    }
  }
}
